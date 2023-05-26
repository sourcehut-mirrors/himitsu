use bufio;
use dirs;
use errors;
use fmt;
use getopt;
use himitsu::client;
use himitsu::query;
use io;
use net::unix;
use net;
use os;
use path;
use shlex;
use strings;
use strio;
use unix::tty;

type flag = enum uint {
	ONE = 1 << 0,
	DECRYPT = 1 << 1,
};

fn write_item(
	out: io::handle,
	items: str,
	field: str
) (void | io::error) = {
	if (field == "") {
		fmt::fprintln(out, items)!;
		return;
	};
	let items = shlex::split(items)!;
	defer strings::freeall(items);
	let query = query::parse_items(items)!;
	for (let i = 0z; i < len(query.items); i += 1) {
		let item = query.items[i];
		if (item.key != field) {
			continue;
		};
		fmt::fprintln(out, item.value)?;
	};
};

export fn main() void = {
	let usage: [_]getopt::help = [
		"secure key store client",
		('1', "only accept one match"),
		('a', "add a key"),
		('d', "decrypt private keys"),
		('D', "delete matching keys"),
		('F', "field", "select a field for output"),
		('Q', "terminate the daemon (if started with -D)"),
		"<query>",
	];
	const cmd = getopt::parse(os::args, usage...);
	defer getopt::finish(&cmd);

	let op = client::operation::QUERY;
	let flags: flag = 0, field = "";
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case '1' =>
			flags |= flag::ONE;
		case 'a' =>
			op = client::operation::ADD;
		case 'd' =>
			flags |= flag::DECRYPT;
		case 'D' =>
			op = client::operation::DEL;
		case 'F' =>
			field = cmd.opts[i].1;
		case 'Q' =>
			op = client::operation::QUIT;
		};
	};

	let buf = path::init()!;
	// TODO: Bubble up dirs::runtime errors
	const sockpath = path::set(&buf, dirs::runtime()!, "himitsu")!;
	let conn = match (unix::connect(sockpath)) {
	case let s: net::socket =>
		yield s;
	case errors::noentry =>
		fmt::fatal("error: himitsud connection failed (is it running?)");
	case let e: net::error =>
		fmt::fatal("error:", net::strerror(e));
	};
	defer io::close(conn)!;

	if (op == client::operation::ADD && len(cmd.args) == 0) {
		if (tty::isatty(os::stderr_file) && tty::isatty(os::stdin_file)) {
			fmt::errorln("Enter new keys, one per line, then press ^d:")!;
		};
		for (true) {
			match (bufio::scanline(os::stdin)!) {
			case io::EOF => break;
			case let line: []u8 =>
				// NB. Can't defer free(line), causes a
				// use-after-free in fmt::fatal
				const line = strings::fromutf8(line)!;
				const query = match (shlex::split(line)) {
				case let q: []str =>
					yield q;
				case =>
					fmt::fatal("Invalid query:", line);
				};
				defer strings::freeall(query);
				free(line);

				send(conn, client::operation::ADD, flags, field, query);
			};
		};
	} else {
		let query = alloc(cmd.args...);
		defer free(query);
		if (flags & flag::DECRYPT != 0) {
			insert(query[0], "-d");
		};
		send(conn, op, flags, field, query);
	};
};

fn send(
	conn: io::file,
	op: client::operation,
	flags: flag,
	field: str,
	query: []str,
) void = {
	fmt::fprint(conn, switch (op) {
	case client::operation::QUERY =>
		yield "query";
	case client::operation::ADD =>
		yield "add";
	case client::operation::DEL =>
		yield "del";
	case client::operation::QUIT =>
		yield "quit";
	})!;
	for (let i = 0z; i < len(query); i += 1) {
		fmt::fprint(conn, " ")!;
		shlex::quote(conn, query[i])!;
	};
	fmt::fprintln(conn)!;

	let buf = strio::dynamic();
	defer io::close(&buf)!;

	for (let n = 0; true; n += 1) match (bufio::scanline(conn)!) {
	case io::EOF => break;
	case let line: []u8 =>
		// NB. Can't defer free(line), causes a use-after-free in
		// fmt::fatal
		let resp = strings::fromutf8(line)!;
		let resp = strings::cut(resp, " ");
		switch (resp.0) {
		case "key" =>
			if (flags & flag::ONE != 0 && n > 0) {
				fmt::fatal("error: Ambiguous match");
			};
			write_item(&buf, resp.1, field)!;
		case "error" =>
			fmt::fatal("error:", resp.1);
		case "end" =>
			free(line);
			break;
		case =>
			break;
		};
		free(line);
	};

	fmt::print(strio::string(&buf))!;
};
