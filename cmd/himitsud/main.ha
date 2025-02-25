use config;
use fmt;
use getopt;
use io;
use log;
use os::exec;
use os;
use rt;
use secstore;
use strconv;
use strings;
use unix::signal;
use unix;

fn handle(sig: signal::sig, info: *signal::siginfo, ucontext: *opaque) void = {
	io::write(sigwrite, [sig: u8])!;
};

let sigwrite: io::file = -1;

export fn main() void = {
	const cmd = getopt::parse(os::args,
		('C', "path", "config file to use"),
		// TODO: Add note warning against using this to himitsu man page
		('D', "daemonize (fork) after startup"),
		('R', "fd", "notify readiness on file descriptor"),
	);
	defer getopt::finish(&cmd);

	let configpath = "";
	let daemonize = false;
	let ready_fd: (void|io::file) = void;
	for (let opt &.. cmd.opts) {
		switch (opt.0) {
		case 'C' =>
			configpath = opt.1;
		case 'D' =>
			daemonize = true;
		case 'R' =>
			match (strconv::stoi(opt.1)) {
			case let err: (strconv::invalid | strconv::overflow) =>
				fmt::fatalf("Invalid parameter for -R: {}.", strconv::strerror(err));
			case let i: int =>
				ready_fd = i;
			};
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

	const conf = match (config::load(configpath)) {
	case let conf: config::config =>
		yield conf;
	case let err: config::error =>
		fmt::fatal("Failed to load config:", config::strerror(err));
	};
	defer config::finish(&conf);

	const sock = match (bind(&store, &conf, pipe.0, daemonize)) {
	case let s: server =>
		yield s;
	case nomem =>
		fmt::fatal(strerror(nomem));
	};

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

	match (ready_fd) {
	case let f: io::file => {
		io::write(f, strings::toutf8("READY=1\n"))!;
		io::close(f)!;
	};
	case void => void;
	};

	log::println("himitsud running");
	for (dispatch(&sock)) void;
	log::println("himitsud terminated");
};
