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
use memio;
use unix::tty;

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
	let flags: client::flags = 0;
	let field: (str | void) = void;
	let one = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case '1' =>
			one = true;
		case 'a' =>
			op = client::operation::ADD;
		case 'd' =>
			flags |= client::flags::DECRYPT;
		case 'D' =>
			op = client::operation::DEL;
		case 'F' =>
			field = cmd.opts[i].1;
		case 'Q' =>
			op = client::operation::QUIT;
		case =>
			fmt::fatal("Invalid command line option");
		};
	};

	let conn = match (client::connect()) {
	case let s: net::socket =>
		yield s;
	case let e: client::hierror =>
		fmt::fatal(e);
	case let e: io::error =>
		fmt::fatal("error:", io::strerror(e));
	case let e: net::error =>
		match (e) {
		case errors::noentry =>
			fmt::fatal("error: himitsud connection failed (is it running?)");
		case =>
			fmt::fatal("error:", net::strerror(e));
		};
	};
	defer io::close(conn)!;

	if (op == client::operation::ADD && len(cmd.args) == 0) {
		if (tty::isatty(os::stderr_file) && tty::isatty(os::stdin_file)) {
			fmt::errorln("Enter new keys, one per line, then press ^d:")!;
		};
		for (true) {
			match (bufio::read_line(os::stdin)!) {
			case io::EOF => break;
			case let line: []u8 =>
				// NB. Can't defer free(line), causes a
				// use-after-free in fmt::fatal
				const query = memio::fixed(line);
				const query = match (query::parse(&query)) {
				case let q: query::query =>
					yield q;
				case query::invalid =>
					fmt::fatal("Invalid query:", strings::fromutf8(line)!);
				case let err: io::error =>
					abort(); // reading from a fixed buffer shouldn't fail
				};
				defer query::finish(&query);
				free(line);
				send(conn, client::operation::ADD, &query, flags, field, one);
			};
		};
	} else {
		const query = match (query::parse_items(cmd.args)) {
		case let q: query::query =>
			yield q;
		case let err: query::error =>
			fmt::fatal(query::strerror(err));
		};
		defer query::finish(&query);
		send(conn, op, &query, flags, field, one);
	};
};

fn send(
	conn: net::socket,
	op: client::operation,
	query: *query::query,
	flags: client::flags,
	field: (str | void),
	one: bool,
) void = {
	const keys = match (client::query(conn, op, query, flags)) {
	case let k: client::keyiter =>
		yield k;
	case let err: client::error =>
		fmt::fatal("Error executing query:", client::strerror(err));
	};

	let buf = memio::dynamic();
	defer io::close(&buf)!;

	for (let i = 0; true; i += 1) {
		let key = match (client::next(&keys)) {
		case let k: const str =>
			if (one && i > 0) {
				fmt::fatal("Error: ambiguous match");
			};
			yield k;
		case let err: client::error =>
			fmt::fatal("Error executing query:", client::strerror(err));
		case void => break;
		};
		match (field) {
		case let field: str =>
			const items = shlex::split(key)!;
			defer strings::freeall(items);
			const query = query::parse_items(items)!;
			defer query::finish(&query);
			for (let i = 0z; i < len(query.items); i += 1) {
				let item = query.items[i];
				if (item.key == field) {
					fmt::fprintln(&buf, item.value)!;
				};
			};
		case void =>
			fmt::fprintln(&buf, key)!;
		};
	};

	fmt::print(memio::string(&buf)!)!;
};
