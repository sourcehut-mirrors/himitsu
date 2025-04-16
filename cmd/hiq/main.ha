use bufio;
use dirs;
use encoding::utf8;
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

type lockop = enum {
	NONE,
	SOFT,
	HARD,
};

export fn main() void = {
	let usage: [_]getopt::help = [
		"secure key store client",
		('1', "only accept one match"),
		('a', "add a key"),
		('c', "key/value pair", "change the value of a pair. "
			"Can be used multiple times."),
		('d', "decrypt private keys"),
		('F', "field", "select a field for output"),
		('l', "soft lock the keyring"),
		('L', "hard lock the keyring"),
		('Q', "terminate the daemon (if started with -D)"),
		('R', "remove matching keys from the key store"),
		('s', "strict query"),
		"<query>",
	];
	const cmd = getopt::parse(os::args, usage...);
	defer getopt::finish(&cmd);

	let op = client::operation::QUERY;
	let flags: client::flags = 0;
	let field: (str | void) = void;
	let one = false;
	let lock = lockop::NONE;
	let changes: []str = [];

	for (let opt .. cmd.opts) {
		switch (opt.0) {
		case '1' =>
			one = true;
		case 'a' =>
			op = client::operation::ADD;
		case 'c' =>
			op = client::operation::UPDATE;
			append(changes, opt.1)!;
		case 'd' =>
			flags |= client::flags::DECRYPT;
		case 'F' =>
			field = opt.1;
		case 'l' =>
			lock = lockop::SOFT;
		case 'L' =>
			lock = lockop::HARD;
		case 'Q' =>
			op = client::operation::QUIT;
		case 'R' =>
			op = client::operation::DEL;
		case 's' =>
			flags |= client::flags::STRICT;
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

	if (lock != lockop::NONE) {
		const soft = lock == lockop::SOFT;
		match (client::lock(conn, soft)) {
		case void =>
			return;
		case let err: client::error =>
			fmt::fatal("Error executing lock:", client::strerror(err));
		};
	};

	if (op == client::operation::ADD && len(cmd.args) == 0) {
		if (tty::isatty(os::stderr_file) && tty::isatty(os::stdin_file)) {
			fmt::errorln("Enter new keys, one per line, then press ^d:")!;
		};
		let scan = bufio::newscanner(os::stdin);
		defer bufio::finish(&scan);
		for (let line => bufio::scan_line(&scan)) {
			let line = match (line) {
			case let line: const str =>
				yield line;
			case let e: io::error =>
				fmt::fatal("Error reading query", io::strerror(e));
			case utf8::invalid =>
				fmt::fatal("Error: Query is not valid UTF-8");
			};

			const query = match (query::parse_str(line)) {
			case let q: query::query =>
				yield q;
			case query::invalid =>
				// duplicate line to avoid use after free
				fmt::fatal("Invalid query:",
					strings::dup(line)!);
			case query::dupkeys =>
				fmt::fatal("Duplicate keys in query:",
					strings::dup(line)!);
			};
			defer query::finish(&query);
			send(conn, client::operation::ADD, &query, flags, field, one);
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
	match (client::query(conn, op, query, flags)) {
	case let k: client::keyiter =>
		print_keys(&k, field, one);
	case let err: client::error =>
		fmt::fatal("Error executing query:", client::strerror(err));
	};
};

fn print_keys(it: *client::keyiter, field: (str | void) = void, one: bool = false) void = {
	let buf = memio::dynamic();
	defer io::close(&buf)!;

	for (let i = 0; true; i += 1) {
		let key = match (client::next(it)) {
		case let k: query::query =>
			if (one && i > 0) {
				fmt::fatal("Error: ambiguous match");
			};
			yield k;
		case let err: client::error =>
			fmt::fatal("Error executing query:", client::strerror(err));
		case done => break;
		};
		match (field) {
		case let field: str =>
			for (let item &.. key.items) {
				if (item.key == field) {
					fmt::fprintln(&buf, item.value)!;
				};
			};
		case void =>
			query::unparse(&buf, &key)!;
		};
	};

	fmt::print(memio::string(&buf)!)!;
};

fn update(
	conn: net::socket,
	query: *query::query,
	changes: *query::query,
	flags: client::flags,
) void = {
	match (client::update(conn, query, changes, flags)) {
	case let it: client::keyiter =>
		print_keys(&it);
	case let err: client::error =>
		fmt::fatal("Error executing update:", client::strerror(err));
	};
};
