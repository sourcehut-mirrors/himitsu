use bufio;
use bytes;
use fmt;
use io;
use os;
use secstore;
use strings;
use unix::tty;

export fn main() void = {
	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fmt::fatal("Error opening tty:", tty::strerror(err));
	};

	const termios = tty::termios_query(tty)!;
	tty::noecho(&termios)!;
	defer tty::termios_restore(&termios);

	let rbuf: [os::BUFSIZ]u8 = [0...];
	let wbuf: [os::BUFSIZ]u8 = [0...];
	const tty = &bufio::buffered(tty, rbuf, wbuf);
	defer io::close(tty)!;

	fmt::errorln("Initializing a new himitsu secstore.")!;
	fmt::error("Please enter a passphrase: ")!;
	const pass1 = match (bufio::scanline(tty)!) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		fmt::fatal("Error: no passphrase supplied");
	};
	defer free(pass1);
	fmt::errorln()!;

	fmt::error("Please enter the same passphrase again: ")!;
	const pass2 = match (bufio::scanline(tty)!) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		fmt::fatal("Error: no passphrase supplied");
	};
	defer free(pass2);
	fmt::errorln()!;

	if (!bytes::equal(pass1, pass2)) {
		fmt::fatal("Error: passphrases do not match");
	};

	match (secstore::create(pass1)) {
	case let err: secstore::error =>
		fmt::fatal("Error initializing secstore:",
			secstore::strerror(err));
	case let store: secstore::secstore =>
		secstore::close(&store);
	};

	fmt::println("Successfully initialized new secstore.")!;
};
