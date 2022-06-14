use bufio;
use bytes;
use config;
use fmt;
use getopt;
use io;
use log;
use os::exec;
use os;
use rt;
use secstore;
use unix::signal;
use unix::tty;
use unix;

export fn main() void = {
	const cmd = getopt::parse(os::args,
		// TODO: Add note warning against using this to himitsu man page
		('D', "daemonize (fork) after startup"));
	defer getopt::finish(&cmd);

	let daemonize = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = &cmd.opts[i];
		switch (opt.0) {
		case 'D' =>
			daemonize = true;
		case => abort();
		};
	};

	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fmt::fatal("Error opening tty:", tty::strerror(err));
	};

	const termios = tty::termios_query(tty)!;
	tty::noecho(&termios)!;

	// TODO: There should be more convenient ways of starting himitsud
	// TODO: Better manage secure memory with bufio::scanline/mlock/etc
	fmt::error("Please enter your passphrase to unlock the keyring: ")!;
	const pass = bufio::scanline(tty)!;
	tty::termios_restore(&termios);

	const pass = match (pass) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		fmt::errorln()!;
		fmt::fatal("Error: no passphrase supplied");
	};
	fmt::errorln()!;

	const store = match (secstore::open()) {
	case let err: secstore::error =>
		bytes::zero(pass);
		fmt::fatal("Error opening secstore:", secstore::strerror(err));
	case let store: secstore::secstore =>
		yield store;
	};
	const err = secstore::unlock(&store, pass);
	bytes::zero(pass);
	free(pass);

	match (err) {
	case let err: secstore::error =>
		fmt::fatal("Error opening secstore:", secstore::strerror(err));
	case void =>
		yield;
	};
	defer secstore::close(&store);

	signal::block(signal::SIGINT, signal::SIGTERM);
	const sigfd = signal::signalfd(signal::SIGINT, signal::SIGTERM)!;
	defer io::close(sigfd)!;

	const conf = match (config::load()) {
	case let conf: config::config =>
		yield conf;
	case let err: config::error =>
		fmt::fatal("Failed to load config:", config::strerror(err));
	};
	defer config::finish(&conf);

	const sock = bind(&store, &conf, sigfd, daemonize);

	if (daemonize) {
		match (exec::fork()) {
		case let err: exec::error =>
			fmt::fatal("exec failed:", exec::strerror(err));
		case int =>
			log::println("Continuing in child process");
			os::exit(0);
		case void =>
			io::close(os::stdin)!;
			io::close(os::stdout)!;
			io::close(os::stderr)!;
		};
	};

	defer shutdown(&sock);

	const flags = rt::fcntl(sock.sock, rt::F_GETFL, 0)!;
	rt::fcntl(sock.sock, rt::F_SETFL, flags | rt::O_CLOEXEC)!;

	log::println("himitsud running");
	for (dispatch(&sock)) void;
	log::println("himitsud terminated");
};
