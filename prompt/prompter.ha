use bytes;
use bufio;
use errors;
use fmt;
use fs;
use io;
use os::exec;
use os;
use secstore;
use strings;

export type prompter = struct {
	proc: exec::process,
	stdin: io::handle,
	stdout: io::handle,
};

// Prompter operation mode
export type mode = enum {
	DISCLOSE,
	DELETE,
};

// Starts a new prompter session.
export fn newprompter(command: str, args: []str) (prompter | error) = {
	const cmd = exec::cmd(command, args...)?;
	const stdin = exec::pipe();
	const stdout = exec::pipe();
	exec::addfile(&cmd, os::stdin_file, stdin.0);
	exec::addfile(&cmd, os::stdout_file, stdout.1);

	const proc = exec::start(&cmd)?;
	io::close(stdin.0)?;
	io::close(stdout.1)?;

	fmt::fprintln(stdin.1, "version")?;
	match (bufio::scanline(stdout.0)?) {
	case io::EOF =>
		return protoerror;
	case let buf: []u8 =>
		defer free(buf);
		const string = strings::fromutf8(buf);
		if (string != "version 0.0.0") {
			// XXX: Return "unsupported" error instead?
			return protoerror;
		};
	};

	return prompter {
		proc = proc,
		stdin = stdin.1,
		stdout = stdout.0,
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
	case void =>
		yield;
	};
	fmt::fprintln(prompt.stdin)?;
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
	})?;
};

// Waits for a password from the prompter and unlocks the store.
export fn wait_unlock(
	prompt: *prompter,
	store: *secstore::secstore,
) (bool | error) = {
	for (true) match (bufio::scanline(prompt.stdout)?) {
	case io::EOF =>
		break;
	case let buf: []u8 =>
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
