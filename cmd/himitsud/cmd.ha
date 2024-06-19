use memio;
use errors;
use fmt;
use fs;
use getopt;
use himitsu::query;
use himitsu::remember;
use io;
use log;
use os::exec;
use prompt;
use secstore;
use shlex;
use strconv;
use strings;
use time;
use unix::poll::{event};

type servererror = !(io::error | fs::error | exec::error | secstore::error);
type cmderror = !(query::error | prompt::error | getopt::error | ...servererror);

fn strerror(err: cmderror) const str = {
	match (err) {
	case let err: io::error =>
		return io::strerror(err);
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: exec::error =>
		return exec::strerror(err);
	case let err: prompt::error =>
		return prompt::strerror(err);
	case let err: secstore::error =>
		return secstore::strerror(err);
	case let err: query::error =>
		return query::strerror(err);
	};
};

fn exec(serv: *server, client: *client, cmd: str) (void | servererror) = {
	// TODO: Better logging of client activity
	const args = match (shlex::split(cmd)) {
	case shlex::syntaxerr =>
		writefmt(client, "error Invalid command syntax");
		return;
	case let items: []str =>
		yield items;
	};
	defer strings::freeall(args);
	if (len(args) == 0) {
		writefmt(client, "error Invalid command syntax");
		return;
	};

	const cmd = switch (args[0]) {
	case "add" =>
		yield &exec_add;
	case "del" =>
		yield &exec_del;
	case "query" =>
		yield &exec_query;
	case "persist" =>
		yield &exec_persist;
	case "quit" =>
		yield &exec_quit;
	case =>
		writefmt(client, "error Unknown command");
		return;
	};

	match (cmd(serv, client, args)) {
	case let err: cmderror =>
		// XXX: Probably a harec bug
		match (err) {
		case let err: secstore::error =>
			writefmt(client, "error {}", secstore::strerror(err));
		case let err: prompt::error =>
			writefmt(client, "error {}", prompt::strerror(err));
		case let err: query::error =>
			writefmt(client, "error {}", strerror(err));
		case let err: getopt::error =>
			writefmt(client, "error Command {}", getopt::strerror(err));
		case let err: servererror =>
			writefmt(client, "error Internal error");
			return err;
		};
	case void => yield;
	};
};

fn exec_add(serv: *server, client: *client, args: []str) (void | cmderror) = {
	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	if (!prompter_unlock(&prompter)?) {
		writefmt(client, "error Failed to unlock");
		return;
	};

	const q = query::parse_items(args[1..])?;
	defer query::finish(&q);

	// TODO: Prompt user to fill in incomplete keys
	let entry = secstore::add(serv.store, &q)?;
	let buf = memio::dynamic();
	fmt::fprint(&buf, "key ")?;
	secstore::write(serv.store, &buf, entry, false)?;
	fmt::fprintln(&buf, "\nend")?;
	write(client, memio::buffer(&buf));
};

fn exec_del(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"query the key store",
		('s', "strict match"),
		"query..."
	)?;
	defer getopt::finish(&cmd);

	let strict = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case 's' =>
			strict = true;
		case => abort();
		};
	};

	const q = query::parse_items(cmd.args)?;
	defer query::finish(&q);

	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	if (!prompter_unlock(&prompter)?) {
		writefmt(client, "error Failed to unlock");
		return;
	};

	const iter = secstore::query(serv.store, &q, strict);
	let matches: []*secstore::entry = [];
	for (let item => secstore::next(serv.store, &iter)) {
		append(matches, item);
	};

	if (len(matches) > 0) {
		prompter_send_keys(&prompter, matches)?;
		prompter_prompt(&prompter, prompt::mode::DELETE)?;
		if (!prompter_wait(&prompter)?) {
			writefmt(client, "error User declined");
			return;
		};

		secstore::del(serv.store, &q, strict)!;
	};

	writefmt(client, "end");
};

fn exec_query(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"query the key store",
		('d', "decrypt private keys"),
		('r', "options", "Suggested remember options"),
		('s', "strict match"),
		"query..."
	)?;
	defer getopt::finish(&cmd);

	let decrypt = false;
	let strict = false;
	let remopts: []remember::option = [];
	defer free(remopts);

	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = cmd.opts[i];
		switch (opt.0) {
		case 'd' =>
			decrypt = true;
		case 'r' =>
			remopts = parse_remopts(opt.1)?;
		case 's' =>
			strict = true;
		case => abort();
		};
	};

	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	if (serv.store.state == secstore::state::HARD_LOCKED
			&& !prompter_unlock(&prompter)?) {
		writefmt(client, "error Failed to unlock");
		return;
	};

	const q = query::parse_items(cmd.args)?;
	defer query::finish(&q);

	const iter = secstore::query(serv.store, &q, strict);
	let matches: []*secstore::entry = [];
	defer free(matches);

	for (let item => secstore::next(serv.store, &iter)) {
		append(matches, item);
	};

	let unrem: []*secstore::entry = [];
	let entry_refused = false;
	defer free(unrem);

	if (decrypt && !is_remembered(client, &q)) {
		unrem = filter_unremembered(client, matches, &entry_refused);
	};

	if (len(matches) > 0 && decrypt && len(unrem) > 0) {
		if (serv.store.state == secstore::state::SOFT_LOCKED
				&& !prompter_unlock(&prompter)?) {
			writefmt(client, "error Failed to unlock");
			return;
		};

		prompter_send_keys(&prompter, unrem)?;

		if (prompter_version(&prompter)? >= prompt::version::REMEMBER
				&& !entry_refused) {
			prompter_send_remember(&prompter, remopts)?;
		};

		prompter_prompt(&prompter, prompt::mode::DISCLOSE)?;

		if (prompter_version(&prompter)? >= prompt::version::REMEMBER) {
			match (prompter_wait_remember(&prompter)?) {
			case remember::skip => void;
			case let r: remember::option =>
				for (let m .. matches) {
					let query = secstore::entry_to_query(m);
					add_remember(client, query, r, true);
				};
			};
		};

		if (!prompter_wait(&prompter)?) {
			writefmt(client, "error User declined");
			return;
		};
	};

	let buf = memio::dynamic();
	defer io::close(&buf)!;
	for (let i = 0z; i < len(matches); i += 1) {
		fmt::fprint(&buf, "key ")?;
		secstore::write(serv.store, &buf, matches[i], decrypt)?;
		io::write(&buf, ['\n'])?;
	};
	fmt::fprintln(&buf, "end")?;

	writebuf(client, memio::buffer(&buf));
};


fn exec_quit(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"Stops daemon. Only possible in daemon mode.",
	)?;
	defer getopt::finish(&cmd);

	if (!serv.daemonized) {
		writefmt(client, "error Server is not damonized, use a service manager");
		return;
	};
	serv.terminate = true;
};

fn exec_persist(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"persist a query for future disclosures",
		('r', "options", "Suggested remember options"),
		('s', "Save as strict query"),
		"query..."
	)?;
	defer getopt::finish(&cmd);

	let remopts: []remember::option = [];
	defer free(remopts);

	let strict = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = cmd.opts[i];
		switch (opt.0) {
		case 'r' =>
			remopts = parse_remopts(opt.1)?;
		case 's' =>
			strict = true;
		case => abort();
		};
	};

	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	const q = query::parse_items(cmd.args)?;
	defer query::finish(&q);

	match (find_remember(client, &q)) {
	case remember::skip => void;
	case let o: remember::option =>
		writefmt(client, "persist {}", remember::stroption(o));
		return;
	};

	if (prompter_version(&prompter)? < prompt::version::REMEMBER) {
		writefmt(client, "error Not supported by prompter");
		return;
	};

	prompter_send_query(&prompter, &q)?;
	prompter_send_remember(&prompter, remopts)?;
	prompter_prompt(&prompter, prompt::mode::PERSIST)?;

	const result = prompter_wait_remember(&prompter)?;

	if (!prompter_wait(&prompter)?) {
		writefmt(client, "persist skip");
		return;
	};

	match (result) {
	case remember::skip =>
		writefmt(client, "persist skip");
	case let r: remember::option =>
		add_remember(client, query::dup_pub(&q), r, strict);
		writefmt(client, "persist {}", remember::stroption(r));
	};
};

