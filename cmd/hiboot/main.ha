use bufio;
use fmt;
use io;
use linux::keyctl;
use os;
use os::exec;
use secstore;
use strings;
use types;
use unix::passwd;
use unix::tty;
use unix;

export fn main() void = {
	if (unix::getuid() != 0) {
		fmt::fatal("Error: hiboot should run as the root user");
	};

	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fmt::fatal("Error opening TTY:", tty::strerror(err));
	};

	const scan = bufio::newscanner(tty, types::SIZE_MAX);
	defer bufio::finish(&scan);

	for (true) {
		fmt::fprintf(tty, "{} login: ", os::hostname())!;
		const username = match (bufio::scan_line(&scan)!) {
		case let line: const str =>
			yield strings::dup(line);
		case io::EOF =>
			abort();
		};
		defer free(username);

		const termios = tty::termios_query(tty)!;
		tty::noecho(&termios)!;

		fmt::fprintf(tty, "Password: ")!;
		const password = match (bufio::scan_line(&scan)!) {
		case let line: const str =>
			yield line;
		case io::EOF =>
			abort();
		};
		fmt::fprintln(tty)!;
		tty::termios_restore(&termios);

		const user = match (passwd::getuser(username)) {
		case let user: passwd::pwent =>
			yield user;
		case void =>
			fmt::fprintln(tty, "Incorrect username or password")!;
			continue;
		};

		if (try_unlock(&user, password)) {
			break;
		};

		fmt::fprintln(tty, "Incorrect username or password")!;
	};
};

// Attempts to unlock the keyring and store the password in the Linux keystore.
fn try_unlock(user: *passwd::pwent, password: str) bool = {
	match (exec::fork()!) {
	case let proc: exec::process =>
		const st = exec::wait(&proc)!;
		match (exec::check(&st)) {
		case void =>
			return true;
		case !exec::exit_status =>
			return false;
		};
	case void =>
		yield;
	};

	unix::setuid(user.uid);
	os::setenv("HOME", user.homedir)!;

	const store = match (secstore::open()) {
	case let store: secstore::secstore =>
		yield store;
	case let err: secstore::error =>
		fmt::println("secstore error", secstore::strerror(err))!;
		os::exit(os::status::FAILURE);
	};

	const pass = strings::toutf8(password);
	match (secstore::unlock(&store, pass)) {
	case void =>
		yield;
	case =>
		os::exit(os::status::FAILURE);
	};

	match (keyctl::add_key("user", "himitsu", pass, keyctl::USER_KEYRING)) {
	case keyctl::error =>
		os::exit(os::status::FAILURE);
	case keyctl::serial =>
		yield;
	};

	os::exit(os::status::SUCCESS);
};
