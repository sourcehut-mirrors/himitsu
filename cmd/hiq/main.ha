use bufio;
use dirs;
use fmt;
use getopt;
use himitsu::query;
use io;
use net::unix;
use net;
use os;
use path;
use shlex;
use strings;
use strio;

type flag = enum uint {
	ONE = 1 << 0,
	DECRYPT = 1 << 1,
};

type operation = enum uint {
	QUERY,
	ADD,
	DEL,
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
		"<query>",
	];
	const cmd = getopt::parse(os::args, usage...);
	defer getopt::finish(&cmd);

	let op = operation::QUERY;
	let flags: flag = 0, field = "";
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case '1' =>
			flags |= flag::ONE;
		case 'a' =>
			op = operation::ADD;
		case 'd' =>
			flags |= flag::DECRYPT;
		case 'D' =>
			op = operation::DEL;
		case 'F' =>
			field = cmd.opts[i].1;
		};
	};

	let query = alloc(cmd.args...);
	defer free(query);
	if (flags & flag::DECRYPT != 0) {
		insert(query[0], "-d");
	};

	let buf = path::init();
	const sockpath = path::set(&buf, dirs::state("himitsu"), "socket")!;
	let conn = match (unix::connect(sockpath)) {
	case let s: io::file =>
		yield s;
	case let e: net::error =>
		fmt::fatal(net::strerror(e));
	};
	defer io::close(conn)!;

	fmt::fprint(conn, switch (op) {
	case operation::QUERY =>
		yield "query";
	case operation::ADD =>
		yield "add";
	case operation::DEL =>
		yield "del";
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
		let resp = strings::fromutf8(line);
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
		};
		free(line);
	};

	fmt::print(strio::string(&buf))!;
};
