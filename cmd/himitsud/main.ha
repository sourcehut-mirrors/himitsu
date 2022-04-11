use bufio;
use fmt;
use io;
use secstore;
use unix;
use unix::signal;
use unix::tty;

let stop: io::file = -1;

export fn main() void = {
	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fmt::fatal("Error opening tty: {}", tty::strerror(err));
	};

	const termios = tty::termios_query(tty)!;
	tty::noecho(&termios)!;
	defer tty::termios_restore(&termios);

	// TODO: There should be more convenient ways of starting himitsud
	fmt::error("Please enter your passphrase to unlock the keyring: ")!;
	const pass = match (bufio::scanline(tty)!) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		fmt::errorln()!;
		fmt::fatal("Error: no passphrase supplied");
	};
	defer free(pass);
	fmt::errorln()!;

	tty::termios_restore(&termios);

	const store = match (secstore::open(pass)) {
	case let err: secstore::error =>
		fmt::fatal("Error opening secstore: {}",
			secstore::strerror(err));
	case let store: secstore::secstore =>
		yield store;
	};
	defer secstore::close(&store);

	let pipe = unix::pipe()!;
	stop = pipe.1;
	const sock = bind(pipe.0);
	defer shutdown(&sock);

	signal::handle(signal::SIGINT, &sighandler);
	signal::handle(signal::SIGTERM, &sighandler);

	for (dispatch(&sock)) void;
};

fn sighandler(sig: int, info: *signal::siginfo, uctx: *void) void = {
	io::write(stop, [1])!;
};
