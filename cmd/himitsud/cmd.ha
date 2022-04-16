use bufio;
use errors;
use fmt;
use fs;
use getopt;
use io;
use os::exec;
use query;
use secstore;
use shlex;
use strings;
use unix::poll::{event};

type servererror = !(io::error | fs::error | errors::invalid | exec::error);
type cmderror = !(query::invalid | servererror);

fn strerror(err: cmderror) const str = {
	match (err) {
	case let err: io::error =>
		return io::strerror(err);
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: exec::error =>
		return exec::strerror(err);
	case query::invalid =>
		return "Invalid query syntax";
	case errors::invalid =>
		// TODO: Use a different type than errors::invalid
		return "Keystore decryption failed";
	};
};

fn exec(serv: *server, client: *client, cmd: str) (void | servererror) = {
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
	case "query" =>
		yield &exec_query;
	case =>
		writefmt(client, "error Unknown command");
		return;
	};

	match (cmd(serv, client, args)) {
	case let err: servererror =>
		writefmt(client, "error Internal error");
		return err;
	case query::invalid =>
		// XXX: Update me when there are more client errors
		writefmt(client, "error {}", strerror(query::invalid));
	case void => yield;
	};
};

fn exec_add(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const q = query::parse_items(args[1..])?;
	defer query::finish(&q);
	// TODO: More validation steps here
	secstore::add(serv.store, &q);
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

	let buf = bufio::dynamic(io::mode::WRITE);
	for (let i = 0z; i < len(matches); i += 1) {
		// TODO: Prompt for all matches at once
		if (decrypt) {
			const consent = prompt(serv.store,
				matches[i], prompt_mode::DISCLOSE)?;
			if (!consent) {
				writefmt(client, "error User declined");
				io::close(&buf);
				return;
			};
		};

		fmt::fprint(&buf, "key ")?;
		secstore::write(serv.store, &buf, matches[i], decrypt)?;
		io::write(&buf, ['\n'])?;
	};
	fmt::fprintln(&buf, "done")?;

	writebuf(client, bufio::buffer(&buf));
};
