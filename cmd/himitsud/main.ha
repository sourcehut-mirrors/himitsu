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
use unix;

fn handle(sig: signal::sig, info: *signal::siginfo, ucontext: *opaque) void = {
	io::write(sigwrite, [sig: u8])!;
};

let sigwrite: io::file = -1;

export fn main() void = {
	const cmd = getopt::parse(os::args,
		// TODO: Add note warning against using this to himitsu man page
		('D', "daemonize (fork) after startup"));
	defer getopt::finish(&cmd);

	let daemonize = false;
	for (let opt &.. cmd.opts) {
		switch (opt.0) {
		case 'D' =>
			daemonize = true;
		case => abort();
		};
	};

	const store = match (secstore::open()) {
	case let err: secstore::error =>
		fmt::fatal("Error opening secstore:", secstore::strerror(err));
	case let store: secstore::secstore =>
		yield store;
	};
	defer secstore::close(&store);

	harden();

	let pipe = unix::pipe()!;
	sigwrite = pipe.1;
	signal::handle(signal::sig::INT, &handle);
	signal::handle(signal::sig::TERM, &handle);

	const conf = match (config::load()) {
	case let conf: config::config =>
		yield conf;
	case let err: config::error =>
		fmt::fatal("Failed to load config:", config::strerror(err));
	};
	defer config::finish(&conf);

	const sock = bind(&store, &conf, pipe.0, daemonize);

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
