use bytes;
use bufio;
use fmt;
use io;
use secstore;
use unix;
use unix::signal;
use unix::tty;

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
	fmt::errorln()!;

	tty::termios_restore(&termios);

	const store = secstore::open(pass);
	bytes::zero(pass);
	free(pass);

	const store = match (store) {
	case let err: secstore::error =>
		fmt::fatal("Error opening secstore: {}",
			secstore::strerror(err));
	case let store: secstore::secstore =>
		yield store;
	};
	defer secstore::close(&store);

	const sigfd = signal::signalfd(signal::SIGINT, signal::SIGTERM)!;
	defer io::close(sigfd);
	signal::block(signal::SIGINT, signal::SIGTERM);

	const sock = bind(sigfd);
	defer shutdown(&sock);

	fmt::println("himitsud running")!;
	for (dispatch(&sock)) void;
};
