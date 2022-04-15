use bufio;
use io;
use query;
use secstore;
use shlex;
use strings;
use unix::poll::{event};

fn exec(serv: *server, client: *client, cmd: str) void = {
	// TODO: Better end-to-end error handling
	const items = match (shlex::split(cmd)) {
	case shlex::syntaxerr =>
		reply(serv, client, "error Invalid command syntax\n");
		return;
	case let items: []str =>
		yield items;
	};
	defer strings::freeall(items);
	if (len(items) == 0) {
		reply(serv, client, "error Invalid command syntax\n");
		return;
	};

	switch (items[0]) {
	case "add" =>
		exec_add(serv, client, items[1..]);
	case "query" =>
		exec_query(serv, client, items[1..]);
	case =>
		reply(serv, client, "error Unknown command\n");
	};
};

fn exec_add(serv: *server, client: *client, args: []str) void = {
	const q = match (query::parse_items(args)) {
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

fn exec_query(serv: *server, client: *client, args: []str) void = {
	const q = match (query::parse_items(args)) {
	case query::invalid =>
		disconnect_error(client, "error Invalid query");
		return;
	case let q: query::query =>
		yield q;
	};
	defer query::finish(&q);

	let buf = bufio::dynamic(io::mode::WRITE);
	const iter = secstore::query(serv.store, &q);
	for (true) {
		const item = match (secstore::next(serv.store, &iter)) {
		case let item: *secstore::entry =>
			yield item;
		case void =>
			break;
		};
		secstore::writeplain(&buf, item)!;
		io::write(&buf, ['\n'])!;
	};
	client.wbuf = bufio::buffer(&buf);
	client.state = client_state::WRITE;
	client.pollfd.events = event::POLLOUT | event::POLLHUP;
};
