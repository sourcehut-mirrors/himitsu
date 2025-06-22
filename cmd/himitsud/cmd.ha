use errors;
use config;
use fmt;
use fs;
use getopt;
use himitsu::client;
use himitsu::query;
use himitsu::remember;
use io;
use log;
use memio;
use os::exec;
use prompt;
use secstore;
use shlex;
use strconv;
use strings;
use time;
use unix::poll::{event};

type servererror = !(io::error | fs::error | exec::error | nomem | secstore::error);
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
		writefmt(client, "error Invalid command syntax")?;
		return;
	case let items: []str =>
		yield items;
	};
	defer strings::freeall(args);
	if (len(args) == 0) {
		writefmt(client, "error Invalid command syntax")?;
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
	case "lock" =>
		yield &exec_lock;
	case "status" =>
		yield &exec_status;
	case "update" =>
		yield &exec_update;
	case "set" =>
		yield &exec_set;
	case "quit" =>
		yield &exec_quit;
	case =>
		writefmt(client, "error Unknown command")?;
		return;
	};

	match (cmd(serv, client, args)) {
	case let err: cmderror =>
		// XXX: Probably a harec bug
		match (err) {
		case let err: secstore::error =>
			writefmt(client, "error {}", secstore::strerror(err))?;
		case let err: prompt::error =>
			writefmt(client, "error {}", prompt::strerror(err))?;
		case let err: query::error =>
			writefmt(client, "error {}", strerror(err))?;
		case let err: getopt::error =>
			writefmt(client, "error Command {}", getopt::strerror(err))?;
		case nomem =>
			writefmt(client, "error Out of memory")?;
		case let err: servererror =>
			writefmt(client, "error Internal error")?;
			return err;
		};
	case void => yield;
	};
};

fn exec_add(serv: *server, client: *client, args: []str) (void | cmderror) = {
	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	if (!prompter_unlock(&prompter)?) {
		writefmt(client, "error Failed to unlock")?;
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
		writefmt(client, "error Failed to unlock")?;
		return;
	};

	const iter = secstore::query(serv.store, &q, strict);
	let matches: []*secstore::entry = [];
	for (let item => secstore::next(serv.store, &iter)) {
		append(matches, item)?;
	};

	if (len(matches) > 0) {
		prompter_send_keys(&prompter, matches)?;
		prompter_prompt(&prompter, prompt::mode::DELETE)?;
		if (!prompter_wait(&prompter)?) {
			writefmt(client, "error User declined")?;
			return;
		};

		secstore::del(serv.store, &q, strict)!;
	};

	writefmt(client, "end")?;
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
			// XXX: errors: invalid can not be cast directly
			remopts = match (remember::parse_options(opt.1)) {
			case let o: []remember::option =>
				yield o;
			case errors::invalid =>
				return errors::invalid: io::error;
			};
		case 's' =>
			strict = true;
		case => abort();
		};
	};

	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	if (secstore::get_state(serv.store) == secstore::state::HARD_LOCKED
			&& !prompter_unlock(&prompter)?) {
		writefmt(client, "error Failed to unlock")?;
		return;
	};

	const q = query::parse_items(cmd.args)?;
	defer query::finish(&q);

	const iter = secstore::query(serv.store, &q, strict);
	let matches: []*secstore::entry = [];
	defer free(matches);

	for (let item => secstore::next(serv.store, &iter)) {
		append(matches, item)?;
	};

	let unrem: []*secstore::entry = [];
	let entry_refused = false;
	defer free(unrem);

	const remembered = is_remembered(client, &q);
	if (decrypt && !remembered) {
		unrem = filter_unremembered(client, matches, &entry_refused)?;
	} else if (decrypt && remembered) {
		config::notify_reuse(serv.conf, &q);
	};

	if (len(matches) > 0 && decrypt && len(unrem) > 0) {
		if (secstore::get_state(serv.store) == secstore::state::SOFT_LOCKED
				&& !prompter_unlock(&prompter)?) {
			writefmt(client, "error Failed to unlock")?;
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
					let query = secstore::entry_to_query(m)?;
					add_remember(client, query, r, true)?;
				};
			};
		};

		if (!prompter_wait(&prompter)?) {
			writefmt(client, "error User declined")?;
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

	writebuf(client, memio::buffer(&buf))?;
};

fn exec_update(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"start the update process",
		('s', "strict match"),
		"query..."
	)?;
	defer getopt::finish(&cmd);

	let q = query::parse_items(cmd.args)?;

	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = cmd.opts[i];
		switch (opt.0) {
		case 's' =>
			q.strict = true;
		case => abort();
		};
	};

	client.qupdate = q;
	writefmt(client, "update")?;
};

fn exec_set(serv: *server, client: *client, args: []str) (void | cmderror) = {
	defer client.qupdate = void;
	const cmd = getopt::tryparse(args,
		"set values to entries queried by the update command"
		"query..."
	)?;
	defer getopt::finish(&cmd);

	let changes = query::parse_items(cmd.args)?;
	defer query::finish(&changes);

	let prompter = new_prompter(serv);
	defer prompter_close(&prompter);

	if (!prompter_unlock(&prompter)?) {
		writefmt(client, "error Failed to unlock")?;
		return;
	};

	let qupdate = match (client.qupdate) {
	case void =>
		writefmt(client, "error Update command required before calling set.")?;
		return;
	case let q: query::query =>
		yield q;
	};

	let updated: []query::query = [];
	defer {
		for (let q &.. updated) query::finish(q);
		free(updated);
	};

	prompter_send_update(&prompter, &changes)?;

	const iter = secstore::query(serv.store, &qupdate, qupdate.strict);
	for (let m => secstore::next(serv.store, &iter)) {
		prompter_send_keys(&prompter, [m])?;

		let q = secstore::entry_to_query(m, true)?;

		let qok = false;
		defer if (!qok) query::finish(&q);

		for (let c .. changes.items) {
			let add = c.value != "";
			for (let i = 0z; i < len(q.items); i += 1) {
				if (q.items[i].key != c.key) {
					continue;
				};

				if (add) {
					let v = strings::dup(c.value)?;
					q.items[i].value = v;
					add = false;
				} else {
					delete(q.items[i]);
				};
				break;
			};

			if (add) {
				let dp = query::dup_pair(&c)?;
				if (append(q.items, dp) is nomem) {
					query::finish_pair(&dp);
					return nomem;
				};
			};
		};

		append(updated, q)?;
		qok = true;
	};

	prompter_prompt(&prompter, prompt::mode::UPDATE)?;
	if (!prompter_wait(&prompter)?) {
		writefmt(client, "error User declined")?;
		return;
	};

	secstore::del(serv.store, &qupdate, qupdate.strict)!;

	let buf = memio::dynamic();
	for (let u .. updated) {
		let entry = match (secstore::add(serv.store, &u)) {
		case let e: *secstore::entry =>
			yield e;
		case secstore::dupentry =>
			// changing values can result in duplicates.
			// TODO should the user be notified about this?
			continue;
		case let e: secstore::error =>
			// if this fails, data has been lost. To fix this
			// properly, we have to rethink how we store entries
			// and/or introduce some kind of transaction system.
			return e;
		};

		fmt::fprint(&buf, "key ")?;
		secstore::write(serv.store, &buf, entry, false)?;
		fmt::fprintln(&buf)?;
	};
	fmt::fprintln(&buf, "end")?;
	write(client, memio::buffer(&buf));
};

fn exec_status(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"Request status.",
	)?;
	defer getopt::finish(&cmd);

	let statestr = switch (secstore::get_state(serv.store)) {
	case secstore::state::UNLOCKED =>
		yield "unlocked";
	case secstore::state::SOFT_LOCKED =>
		yield "soft_locked";
	case secstore::state::HARD_LOCKED =>
		yield "hard_locked";
	};

	writefmt(client, "status {}", statestr)?;
};

fn exec_quit(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"Stops daemon. Only possible in daemon mode.",
	)?;
	defer getopt::finish(&cmd);

	if (!serv.daemonized) {
		writefmt(client, "error Server is not damonized, use a service manager")?;
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
			// XXX: errors: invalid can not be cast directly
			remopts = match (remember::parse_options(opt.1)) {
			case let o: []remember::option =>
				yield o;
			case errors::invalid =>
				return errors::invalid: io::error;
			};
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
		writefmt(client, "persist {}", remember::stroption(o))?;
		return;
	};

	if (prompter_version(&prompter)? < prompt::version::REMEMBER) {
		writefmt(client, "error Not supported by prompter")?;
		return;
	};

	prompter_send_query(&prompter, &q)?;
	prompter_send_remember(&prompter, remopts)?;
	prompter_prompt(&prompter, prompt::mode::PERSIST)?;

	const result = prompter_wait_remember(&prompter)?;

	if (!prompter_wait(&prompter)? && !(result is remember::refuse)) {
		writefmt(client, "persist skip")?;
		return;
	};

	match (result) {
	case remember::skip =>
		writefmt(client, "persist skip")?;
	case let r: remember::option =>
		add_remember(client, query::dup_pub(&q)?, r, strict)?;
		writefmt(client, "persist {}", remember::stroption(r))?;
	};
};

fn exec_lock(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::tryparse(args,
		"lock the key store",
		('s', "soft lock: only lock secret values"),
		"query..."
	)?;
	defer getopt::finish(&cmd);

	let soft = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = cmd.opts[i];
		switch (opt.0) {
		case 's' =>
			soft = true;
		case => abort();
		};
	};

	if (soft) {
		secstore::softlock(serv.store);
	} else {
		secstore::lock(serv.store);
	};
	writefmt(client, "locked")?;
};
