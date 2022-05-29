use bufio;
use bytes;
use dirs;
use errors;
use fmt;
use fs;
use io;
use os;
use path;
use secstore;
use strings;
use unix::tty;

// XXX: Distros may want to modify the default config
const conf: str = `[himitsud]
prompter=hiprompt-gtk-py`;

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

	// TODO: Prompt before overwriting existing secstore
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

fn writeconf() void = {
	let buf = path::init();
	const confdir = dirs::config("himitsu");
	match (os::mkdirs(confdir, 0o755)) {
	case let err: fs::error =>
		fmt::fatal("Error creating config directory:", fs::strerror(err));
	case void =>
		yield;
	};

	path::set(&buf, confdir, "config.ini")!;
	const confpath = path::string(&buf);
	const file = match (os::create(confpath, 0o644, fs::flags::EXCL)) {
	case let file: io::file =>
		yield file;
	case errors::exists =>
		fmt::println("Config file already exists (not overwriting it)")!;
		return;
	case let err: fs::error =>
		fmt::fatal("Error creating config file:", fs::strerror(err));
	};
	defer io::close(file)!;

	match (io::writeall(file, strings::toutf8(conf))) {
	case let err: io::error =>
		fmt::fatal("Error writing config file:", io::strerror(err));
	case size =>
		yield;
	};

	fmt::println("Wrote config file to {}", confpath)!;
};
