use ascii;
use bufio;
use bytes;
use dirs;
use errors;
use fmt;
use fs;
use io;
use memio;
use os;
use path;
use secstore;
use strings;
use unix::tty;
use getopt;
use net::unix;
use net;

// XXX: Distros may want to modify the default config
const conf: str = `[himitsud]
prompter=hiprompt-gtk`;

export fn main() void = {

	const cmd = getopt::parse(os::args,
		"himitsu-store",
		('i', "Initialize the secstore."),
		('r', "Change master key and re-encrypt the secstore."),
	);
	defer getopt::finish(&cmd);

	let re = false;
	let initstore = false;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = cmd.opts[i];
		switch (opt.0) {
		case 'r' =>
			re = true;
		case 'i' =>
			initstore = true;
		case =>
			fmt::fatal("Invalid command line option");
		};
	};

	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fmt::fatal("Error opening tty:", tty::strerror(err));
	};

	const termios = tty::termios_query(tty)!;
	defer tty::termios_restore(&termios);

	let rbuf: [os::BUFSZ]u8 = [0...];
	let wbuf: [os::BUFSZ]u8 = [0...];
	const tty = &bufio::init(tty, rbuf, wbuf);
	defer io::close(tty)!;

	if (initstore) {
		init(&termios, tty);
		return;
	};

	if (re) {
		reencrypt(&termios, tty);
		return;
	};

	fmt::fatalf("No action specified");
};

fn init(termios: *tty::termios, tty: io::handle) void = {
	match (secstore::open()) {
	case let store: secstore::secstore =>
		secstore::close(&store);
		fmt::error("A himitsu secstore already exists. Do you want to overwrite it? [y/N]: ")!;
		const answer = match (bufio::read_line(tty)!) {
		case let buf: []u8 =>
			yield buf;
		case io::EOF =>
			fmt::fatal("Skipping secstore initialization.");
		};
		defer free(answer);
		const answer = strings::fromutf8(answer)!;
		if (ascii::strcasecmp(answer, "y") != 0 && ascii::strcasecmp(answer, "yes") != 0) {
			fmt::fatal("Skipping secstore initialization.");
		};
		match (secstore::remove()) {
		case void => void;
		case let err: fs::error =>
			fmt::fatal("Error removing existing secstore:", fs::strerror(err));
		};
	case let err: secstore::error =>
		if (!(err is fs::error && err: fs::error is errors::noentry)) {
			fmt::fatal("Error:", secstore::strerror(err));
		};
	};

	tty::noecho(termios)!;

	fmt::errorln("Initializing a new himitsu secstore.")!;
	fmt::error("Please enter a passphrase: ")!;
	const pass1 = match (bufio::read_line(tty)!) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		fmt::fatal("Error: no passphrase supplied");
	};
	defer free(pass1);
	fmt::errorln()!;

	fmt::error("Please enter the same passphrase again: ")!;
	const pass2 = match (bufio::read_line(tty)!) {
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
	writeconf();
};


fn writeconf() void = {
	let buf = path::init()!;
	const confdir = dirs::config("himitsu");
	match (os::mkdirs(confdir, 0o755)) {
	case let err: fs::error =>
		fmt::fatal("Error creating config directory:", fs::strerror(err));
	case void =>
		yield;
	};

	path::set(&buf, confdir, "config.ini")!;
	const confpath = path::string(&buf);
	const file = match (os::create(confpath, 0o644, fs::flag::WRONLY,
		fs::flag::EXCL)) {
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

	fmt::println("Wrote config file to", confpath)!;
};

fn reencrypt(termios: *tty::termios, tty: io::handle) void = {
	fmt::errorln("Re-encrypting the secstore.\n")!;
	fmt::errorln("There are not many safeguards in effect, so please read carefully.")!;
	fmt::errorln()!;
	fmt::errorfln(
		"Make sure that no himitsud process is currently running. The current\n"
		"secstore will be moved to himitsu.old in our data directory:\n\n"
		"\t{}\n\nIf the process fails in between, make sure that himitsu.new in the \n"
		"data directory is removed and try again.\n",
		dirs::data(""),
	)!;

	tty::noecho(termios)!;
	fmt::error("Please enter your passphrase: ")!;
	const pass = match (bufio::read_line(tty)!) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		fmt::fatal("Error: no passphrase supplied");
	};
	defer free(pass);
	fmt::errorln()!;

	if (checkhimitsud()) {
		fmt::fatal("Error: Please make sure that himitsud is not running");
	};

	match (secstore::reencrypt(pass)) {
	case let e: secstore::error =>
		fmt::fatal("Error:", secstore::strerror(e));
	case void =>
		yield;
	};

	fmt::errorln(
		"\nSecstore has been re-encrypted. If everything works,you may remove the\n"
		"himitsu.old folder from your data directory"
	)!;
};

// check whether himitsud is running
fn checkhimitsud() bool = {
	let buf = path::init()!;
	let rtdir = match (dirs::runtime()) {
	case let e: fs::error =>
		fmt::fatal("error getting runtime dir: ", fs::strerror(e));
	case let d: str =>
		yield d;
	};

	const sockpath = path::set(&buf, rtdir, "himitsu")!;
	let conn = match (unix::connect(sockpath)) {
	case errors::noentry =>
		return false;
	case let e: net::error =>
		fmt::fatal("error:", net::strerror(e));
	case let s: net::socket =>
		yield s;
	};
	defer io::close(conn)!;
	return true;
};
