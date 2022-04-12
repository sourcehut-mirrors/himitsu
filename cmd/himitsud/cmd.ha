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
	case "query" =>
		exec_query(serv, client, items[1..]);
	case =>
		reply(serv, client, "error unknown command\n");
	};
};

fn exec_query(serv: *server, client: *client, args: []str) void = {
	void;
};
