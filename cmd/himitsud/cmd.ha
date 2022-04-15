use bufio;
use errors;
use fs;
use getopt;
use io;
use query;
use secstore;
use shlex;
use strings;
use unix::poll::{event};

type cmderror = !(io::error | fs::error | errors::invalid);

fn exec(serv: *server, client: *client, cmd: str) void = {
	// TODO: Better end-to-end error handling
	const args = match (shlex::split(cmd)) {
	case shlex::syntaxerr =>
		reply(serv, client, "error Invalid command syntax\n");
		return;
	case let items: []str =>
		yield items;
	};
	defer strings::freeall(args);
	if (len(args) == 0) {
		reply(serv, client, "error Invalid command syntax\n");
		return;
	};

	match (switch (args[0]) {
	case "add" =>
		yield exec_add(serv, client, args);
	case "query" =>
		yield exec_query(serv, client, args);
	case =>
		reply(serv, client, "error Unknown command\n");
		return;
	}) {
	// TODO: These errors should be prefixed with "error"
	case let err: io::error =>
		reply(serv, client, io::strerror(err));
	case let err: fs::error =>
		reply(serv, client, fs::strerror(err));
	// TODO: We can probably come up with something more semantic than
	// errors::invalid for this
	case errors::invalid =>
		reply(serv, client, "error Key decryption failed");
	case void => yield;
	};
};

fn exec_add(serv: *server, client: *client, args: []str) (void | cmderror) = {
	const q = match (query::parse_items(args[1..])) {
	case query::invalid =>
		disconnect_error(client, "error Invalid query");
		return;
	case let q: query::query =>
		yield q;
	};
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

	let private = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case 'd' =>
			private = true;
		case => abort();
		};
	};

	const q = match (query::parse_items(cmd.args)) {
	case query::invalid =>
		disconnect_error(client, "error Invalid query");
		return;
	case let q: query::query =>
		yield q;
	};
	defer query::finish(&q);

	// TODO: Prompt user for consent if private = true

	let buf = bufio::dynamic(io::mode::WRITE);
	const iter = secstore::query(serv.store, &q);
	for (true) {
		const item = match (secstore::next(serv.store, &iter)) {
		case let item: *secstore::entry =>
			yield item;
		case void =>
			break;
		};
		secstore::write(serv.store, &buf, item, private)?;
		io::write(&buf, ['\n'])?;
	};
	client.wbuf = bufio::buffer(&buf);
	client.state = client_state::WRITE;
	client.pollfd.events = event::POLLOUT | event::POLLHUP;
};
