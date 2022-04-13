use query;
use secstore;
use shlex;
use strings;

fn exec(serv: *server, client: *client, cmd: str) void = {
	const items = match (shlex::split(cmd)) {
	case shlex::syntaxerr =>
		reply(serv, client, "error syntax\n");
		return;
	case let items: []str =>
		yield items;
	};
	defer strings::freeall(items);
	if (len(items) == 0) {
		reply(serv, client, "error syntax\n");
		return;
	};

	switch (items[0]) {
	case "add" =>
		exec_add(serv, client, items[1..]);
	case "query" =>
		exec_query(serv, client, items[1..]);
	case =>
		reply(serv, client, "error unknown command\n");
	};
};

fn exec_add(serv: *server, client: *client, args: []str) void = {
	const q = match (query::parse_items(args)) {
	case query::invalid =>
		disconnect_error(client, "error query Invalid query");
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
		disconnect_error(client, "error query Invalid query");
		return;
	case let q: query::query =>
		yield q;
	};
	defer query::finish(&q);
	// TODO
};
