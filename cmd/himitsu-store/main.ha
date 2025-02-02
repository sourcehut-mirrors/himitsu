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
use himitsu::query;
use strings;
use unix::tty;
use getopt;
use net::unix;
use net;

// XXX: Distros may want to modify the default config
const conf: str = `[himitsud]
prompter=hiprompt-gtk
`;

export fn main() void = {

	const cmd = getopt::parse(os::args,
		"himitsu-store",
		('i', "Initialize the secstore."),
		('r', "Change master key and re-encrypt the secstore."),
		('c', "Change the master password"),
	);
	defer getopt::finish(&cmd);

	let re = false;
	let initstore = false;
	let chpw = false;
	for (let opt .. cmd.opts) {
		switch (opt.0) {
		case 'r' =>
			re = true;
		case 'i' =>
			initstore = true;
		case 'c' =>
			chpw = true;
		case =>
			fmt::fatal("Invalid command line option");
		};
	};

	if ((chpw || re) && initstore) {
		fmt::fatal("Can not use -i with -c or -r");
	};

	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fmt::fatal("Error opening tty:", tty::strerror(err));
	};

	const termios = tty::termios_query(tty)!;

	let rbuf: [os::BUFSZ]u8 = [0...];
	let wbuf: [os::BUFSZ]u8 = [0...];
	const tty = &bufio::init(tty, rbuf, wbuf);
	defer io::close(tty)!;

	if (initstore) {
		init(&termios, tty);
		return;
	};

	if (re) {
		reencrypt(&termios, tty, chpw);
		return;
	};

	if (chpw) {
		fmt::fatalf("Changing password currently only works in combination with -r");
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
	defer tty::termios_restore(termios);

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
	const file = match (os::create(confpath, 0o644,
			fs::flag::WRONLY | fs::flag::EXCL)) {
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

fn reencrypt(termios: *tty::termios, tty: io::handle, chpw: bool) void = {
	fmt::errorln("Re-encrypting the secstore.\n")!;
	fmt::errorln("Make sure that no himitsud process is currently running.")!;
	fmt::errorln()!;

	tty::noecho(termios)!;
	defer tty::termios_restore(termios);

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
		fmt::fatal("Error: Himitsud is running.");
	};

	const newpass: []u8 = if (!chpw) {
		yield [];
	} else {
		fmt::error("Please enter your new passphrase: ")!;
		const pass1 = match (bufio::read_line(tty)!) {
		case let buf: []u8 =>
			yield buf;
		case io::EOF =>
			fmt::fatal("Error: no passphrase supplied");
		};
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

		yield pass1;
	};
	defer free(newpass);

	match (reencrypt_move(pass, if (len(newpass) != 0) newpass else pass)) {
	case void =>
		yield;
	case let e: secstore::error =>
		fmt::fatal("Could not reencrypt:", secstore::strerror(e));
	};
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

// Generates a new master key and re-encrypts the secstore.
export fn reencrypt_move(oldpass: []u8, newpass: []u8) (void | secstore::error)  = {
	let olddir = strings::dup(dirs::data("himitsu"))?;
	fmt::errorln("Unlocking store at", olddir)!;
	let oldstore = secstore::openat(olddir)?;
	secstore::unlock(&oldstore, oldpass)?;
	let closed = false;
	defer if (!closed) secstore::close(&oldstore);

	let newdir = strings::dup(dirs::data("himitsu.new"))?;
	fmt::errorln("Creating new store at", newdir)!;
	let store = secstore::createat(newpass, newdir)!;
	defer if (!closed) secstore::close(&store);

	fmt::error("Copying all entries to the new store... ")!;
	const q = query::query { ... };
	const iter = secstore::query(&oldstore, &q, false);
	for (let item => secstore::next(&oldstore, &iter)) {
		let buf = memio::dynamic();
		defer io::close(&buf)!;
		secstore::write(&oldstore, &buf, item, true)!;

		io::seek(&buf, 0, io::whence::SET)!;

		let iq = query::parse(&buf)!;
		defer query::finish(&iq);
		secstore::add(&store, &iq)!;
		yield item;
	};

	secstore::close(&oldstore);
	secstore::close(&store);
	closed = true;

	fmt::errorln("Done!")!;

	let dir = strings::dup(dirs::data("himitsu"))?;
	defer free(dir);
	let dirold = strings::dup(dirs::data("himitsu.old"))?;
	defer free(dirold);

	fmt::errorln("Backing up current store to", dirold)!;
	match (os::rename(dir, dirold)) {
	case let e: fs::error =>
		fmt::fatalf("Backup failed: {}", fs::strerror(e));
	case =>
		yield;
	};

	fmt::errorln("Moving new store to", dir)!;
	let dirnew = strings::dup(dirs::data("himitsu.new"))?;
	defer free(dirnew);
	match (os::rename(dirnew, dir)) {
	case let e: fs::error =>
		fmt::fatalf("Moving himitsu.new to himitsu failed: {}",
			fs::strerror(e));
	case =>
		yield;
	};

	fmt::errorln(
		"\nSecstore has been re-encrypted. If everything works, you may remove",
		dirold
	)!;
};

