use bytes;
use bufio;
use errors;
use fmt;
use fs;
use himitsu::query;
use himitsu::remember;
use io;
use memio;
use os::exec;
use os;
use secstore;
use strings;
use strconv;

export type prompter = struct {
	proc: exec::process,
	stdin: io::handle,
	stdout: io::handle,
	version: u32,
};

// Prompter operation mode
export type mode = enum {
	DISCLOSE,
	DELETE,
	PERSIST,
};

// Starts a new prompter session.
export fn newprompter(command: str, args: []str) (prompter | error) = {
	const cmd = exec::cmd(command, args...)?;
	const stdin = exec::pipe();
	const stdout = exec::pipe();
	exec::addfile(&cmd, os::stdin_file, stdin.0);
	exec::addfile(&cmd, os::stdout_file, stdout.1);
	exec::addfile(&cmd, os::stderr_file, exec::nullfd);

	const proc = exec::start(&cmd)?;
	io::close(stdin.0)?;
	io::close(stdout.1)?;

	fmt::fprintln(stdin.1, "version")?;
	let version = match (bufio::read_line(stdout.0)?) {
	case io::EOF =>
		return protoerror;
	case let buf: []u8 =>
		defer free(buf);
		const string = strings::fromutf8(buf)!;
		yield parse_version(string)?;
	};

	return prompter {
		proc = proc,
		stdin = stdin.1,
		stdout = stdout.0,
		version = version,
	};
};

// Sends a key to the prompter.
export fn sendkey(
	prompt: *prompter,
	store: *secstore::secstore,
	entry: *secstore::entry,
) (void | error) = {
	fmt::fprintf(prompt.stdin, "key ")?;
	match (secstore::write(store, prompt.stdin, entry, false)) {
	case secstore::badstore =>
		abort(); // Did not request decryption
	case let err: fs::error =>
		return err;
	case let err: io::error =>
		return err;
	case size =>
		yield;
	};
	fmt::fprintln(prompt.stdin)?;
};

// Sends recommended remember options, if the prompter supports it.
export fn send_remember(
	prompt: *prompter,
	options: []remember::option,
) (void | error) = {
	if (prompt.version < version::REMEMBER) {
		return;
	};

	for (let o .. options) {
		match (o) {
		case let t: remember::timeout =>
			fmt::fprintln(prompt.stdin, "remember timeout", t: i64)?;
		case let r: remember::option =>
			fmt::fprintln(prompt.stdin, "remember",
				remember::stroption(r: remember::option))?;
		};
	};
};

// Awaits a remember response. Returns void if none received.
export fn wait_remember(prompt: *prompter) (remember::option | error) = {
	if (prompt.version < version::REMEMBER) {
		return remember::refuse;
	};

	let buf = match (bufio::read_line(prompt.stdout)?) {
	case let b: []u8 =>
		yield b;
	case io::EOF =>
		return remember::skip;
	};

	defer free(buf);

	const string = strings::fromutf8_unsafe(buf);

	const (cmd, args) = strings::cut(string, " ");
	if (cmd != "remember") {
		return protoerror;
	};

	const (method, args) = strings::cut(args, " ");
	switch (method) {
	case "session" =>
		return remember::session;
	case "skip" =>
		return remember::skip;
	case "refuse" =>
		return remember::refuse;
	case "timeout" =>
		match (strconv::stou32(args)) {
		case let t: u32 =>
			return t: remember::timeout;
		case strconv::error =>
			return protoerror;
		};
	case =>
		return protoerror;
	};
};

// Sends a query to the prompter
export fn send_query(
	prompt: *prompter,
	query: *query::query,
) (void | error) = {
	fmt::fprintf(prompt.stdin, "query ")?;
	query::unparse(prompt.stdin, query)?;
};

// Sends an unlock request to the prompter.
export fn unlock(prompt: *prompter) (void | error) = {
	fmt::fprintln(prompt.stdin, "unlock")?;
};

// Sends a "prompt" command to the prompter with the given operating mode.
export fn prompt(prompt: *prompter, mode: mode) (void | io::error) = {
	fmt::fprintfln(prompt.stdin, "prompt {}", switch (mode) {
	case mode::DISCLOSE =>
		yield "disclose";
	case mode::DELETE =>
		yield "delete";
	case mode::PERSIST =>
		yield "persist";
	})?;
};

// Waits for a password from the prompter and unlocks the store.
export fn wait_unlock(
	prompt: *prompter,
	store: *secstore::secstore,
) (bool | error) = {
	for (let buf => bufio::read_line(prompt.stdout)?) {
		defer {
			bytes::zero(buf);
			free(buf);
		};
		const string = strings::fromutf8_unsafe(buf);

		const (cmd, pass) = strings::cut(string, " ");
		if (cmd != "password") {
			return protoerror;
		};
		match (secstore::unlock(store, strings::toutf8(pass))) {
		case void =>
			fmt::fprintln(prompt.stdin, "password correct")?;
			return true;
		case secstore::badpass =>
			fmt::fprintln(prompt.stdin, "password incorrect")?;
		case let err: secstore::error =>
			abort("Unexpected secstore error");
		};
	};
	return false;
};

// Waits for the prompter to complete and returns true if the user consented to
// the operation, or false otherwise.
export fn wait(prompt: *prompter) (bool | error) = {
	close(prompt)?;

	const res = exec::wait(&prompt.proc)?;
	match (exec::check(&res)) {
	case void =>
		return true;
	case let res: !exec::exit_status =>
		match (res) {
		case exec::signaled =>
			// XXX: Could bubble up which signal it was
			return prompterror;
		case let ec: exec::exited =>
			if (ec == 1) {
				return false;
			} else if (ec == 127) {
				return prompterror;
			} else {
				return protoerror;
			};
		};
	};
};

// Closes standard input and standard output of a prompter.
export fn close(prompt: *prompter) (void | error) = {
	io::close(prompt.stdin)?;
	io::close(prompt.stdout)?;
};
