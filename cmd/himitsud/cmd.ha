use bufio;
use errors;
use fmt;
use fs;
use getopt;
use himitsu::query;
use io;
use log;
use os::exec;
use prompt;
use secstore;
use shlex;
use strings;
use unix::poll::{event};

type servererror = !(io::error | fs::error | exec::error | secstore::error);
type cmderror = !(query::invalid | prompt::error | ...servererror);

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
	case query::invalid =>
		return "Invalid query syntax";
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
		case let err: servererror =>
			writefmt(client, "error Internal error");
			return err;
		case let err: prompt::error =>
			writefmt(client, "error {}", prompt::strerror(err));
		case query::invalid =>
			// XXX: Update me when there are more client errors
			writefmt(client, "error {}", strerror(query::invalid));
		};
	case void => yield;
	};
};

fn exec_add(serv: *server, client: *client, args: []str) (void | cmderror) = {
	if (serv.store.state != secstore::state::UNLOCKED) {
		const prompter = prompt::newprompter(serv.conf.prompter[0],
			serv.conf.prompter[1..])?;
		prompt::unlock(&prompter)?;
		if (!prompt::wait_unlock(&prompter, serv.store)?) {
			writefmt(client, "error Failed to unlock");
			return;
		};
		prompt::close(&prompter)?;
	};

	const q = query::parse_items(args[1..])?;
	defer query::finish(&q);
	// TODO: Prompt user to fill in incomplete keys
	let entry = secstore::add(serv.store, &q)!;
	let buf = bufio::dynamic(io::mode::WRITE);
	fmt::fprint(&buf, "key ")?;
	secstore::write(serv.store, &buf, entry, false)?;
	fmt::fprintln(&buf, "\nend")?;
	write(client, bufio::buffer(&buf));
};

fn exec_del(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const q = query::parse_items(args[1..])?;
	defer query::finish(&q);

	let buf = bufio::dynamic(io::mode::WRITE);

	let prompter: (prompt::prompter | void) = void;
	if (serv.store.state != secstore::state::UNLOCKED) {
		const new = prompt::newprompter(serv.conf.prompter[0],
			serv.conf.prompter[1..])?;
		prompt::unlock(&new)?;
		if (!prompt::wait_unlock(&new, serv.store)?) {
			writefmt(client, "error Failed to unlock");
			return;
		};
	};

	const iter = secstore::query(serv.store, &q);
	let matches: []*secstore::entry = [];
	for (true) {
		const item = match (secstore::next(serv.store, &iter)) {
		case let item: *secstore::entry =>
			yield item;
		case void =>
			break;
		};
		fmt::fprint(&buf, "key ")?;
		secstore::write(serv.store, &buf, item, false)?;
		io::write(&buf, ['\n'])?;
		append(matches, item);
	};

	if (len(matches) > 0) {
		const prompter = match (prompter) {
		case let p: prompt::prompter =>
			yield p;
		case void =>
			yield prompt::newprompter(serv.conf.prompter[0],
				serv.conf.prompter[1..])?;
		};
		for (let i = 0z; i < len(matches); i += 1) {
			prompt::sendkey(&prompter, serv.store, matches[i])?;
		};
		prompt::prompt(&prompter, prompt::mode::DELETE)?;
		if (!prompt::wait(&prompter)?) {
			writefmt(client, "error User declined");
			return;
		};

		secstore::del(serv.store, &q)!;
	} else {
		match (prompter) {
		case let p: prompt::prompter =>
			prompt::close(&p)?;
		case void => yield;
		};
	};

	fmt::fprintln(&buf, "end")?;
	writebuf(client, bufio::buffer(&buf));
};

fn exec_query(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const cmd = getopt::parse(args,
		"query the key store",
		('d', "decrypt private keys"),
		"query..."
	);
	defer getopt::finish(&cmd);

	let decrypt = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case 'd' =>
			decrypt = true;
		case => abort();
		};
	};

	let prompter: (prompt::prompter | void) = void;
	if (serv.store.state == secstore::state::HARD_LOCKED) {
		const new = prompt::newprompter(serv.conf.prompter[0],
			serv.conf.prompter[1..])?;
		prompt::unlock(&new)?;
		if (!prompt::wait_unlock(&new, serv.store)?) {
			writefmt(client, "error Failed to unlock");
			return;
		};
		if (!decrypt) {
			prompt::close(&new)?;
		};
		prompter = new;
	};

	const q = query::parse_items(cmd.args)?;
	defer query::finish(&q);

	const iter = secstore::query(serv.store, &q);
	let matches: []*secstore::entry = [];
	for (true) {
		const item = match (secstore::next(serv.store, &iter)) {
		case let item: *secstore::entry =>
			yield item;
		case void =>
			break;
		};
		append(matches, item);
	};

	if (len(matches) > 0 && decrypt) {
		const prompter = match (prompter) {
		case let p: prompt::prompter =>
			yield p;
		case void =>
			yield prompt::newprompter(serv.conf.prompter[0],
				serv.conf.prompter[1..])?;
		};
		for (let i = 0z; i < len(matches); i += 1) {
			prompt::sendkey(&prompter, serv.store, matches[i])?;
		};
		if (serv.store.state == secstore::state::SOFT_LOCKED) {
			prompt::unlock(&prompter)?;
		};
		prompt::prompt(&prompter, prompt::mode::DISCLOSE)?;
		if (serv.store.state == secstore::state::SOFT_LOCKED) {
			if (!prompt::wait_unlock(&prompter, serv.store)?) {
				writefmt(client, "error Failed to unlock");
				return;
			};
		};
		if (!prompt::wait(&prompter)?) {
			writefmt(client, "error User declined");
			return;
		};
	};

	let buf = bufio::dynamic(io::mode::WRITE);
	defer io::close(&buf)!;
	for (let i = 0z; i < len(matches); i += 1) {
		fmt::fprint(&buf, "key ")?;
		secstore::write(serv.store, &buf, matches[i], decrypt)?;
		io::write(&buf, ['\n'])?;
	};
	fmt::fprintln(&buf, "end")?;

	writebuf(client, bufio::buffer(&buf));
};

fn exec_quit(serv: *server, client: *client, args: []str) (void | cmderror) = {
	if (!serv.daemonized) {
		writefmt(client, "error Server is not damonized, use a service manager");
		return;
	};
	serv.terminate = true;
};
