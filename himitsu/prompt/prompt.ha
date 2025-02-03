use bufio;
use encoding::utf8;
use errors;
use himitsu::query;
use himitsu::remember;
use io;
use os;
use strconv;
use strings;

// Prompter protocol version supported by this module.
export def VERSION: (uint, uint, uint) = (0, 0, 2);

export type prompter = struct {
	in: io::handle,
	out: io::handle,
	scan: bufio::scanner,
};

// Initializes a new prompter with stdin/stdout and handles the version
// handshake. Use [[next]] to enumerate prompter commands from the daemon, and
// pass the prompter to [[finish]] to clean up resources after use.
export fn init() (prompter | error) = {
	return init_file(os::stdin, os::stdout);
};

// Initializes a new prompter with the given files for input and output and
// handles the version handshake. Use [[next]] to enumerate prompter commands
// from the daemon, and pass the prompter to [[finish]] to clean up resources
// after use.
export fn init_file(in: io::handle, out: io::handle) (prompter | error) = {
	const p = prompter {
		in = os::stdin,
		out = os::stdout,
		scan = bufio::newscanner(in),
	};
	match (next(&p)?) {
	case let cmd: command =>
		assert(cmd is version);
		reply_version(&p, VERSION)?;
	case io::EOF =>
		return errors::cancelled;
	};
	return p;
};

// Frees resources associated with the prompter. Does not close the underlying
// file handles.
export fn finish(p: *prompter) void = {
	bufio::finish(&p.scan);
};

// Returns the next [[command]] from the prompter, or [[io::EOF]]. Pass the
// return value to [[command_finish]] after use.
export fn next(p: *prompter) (command | io::EOF | error) = {
	const line = match (bufio::scan_line(&p.scan)) {
	case let s: const str =>
		yield s;
	case io::EOF =>
		return io::EOF;
	case let err: io::error =>
		return err;
	case utf8::invalid =>
		return errors::invalid;
	};

	const (cmd, args) = strings::cut(line, " ");
	switch (cmd) {
	case "key" =>
		return query::parse_str(args)?: key;
	case "query" =>
		return query::parse_str(args)?: update;
	case "update" =>
		return query::parse_str(args)?: query;
	case "password" =>
		return (args == "correct"): password;
	case "remember" =>
		const (kind, arg) = strings::cut(args, " ");
		switch (kind) {
		case "session" =>
			return remember::session;
		case "timeout" =>
			match (strconv::stou32(arg)) {
			case let t: u32 =>
				return t: remember::timeout;
			case strconv::error =>
				return errors::invalid;
			};
		case "skip" =>
			return remember::skip;
		case "refuse" =>
			return remember::refuse;
		case =>
			return errors::invalid;
		};
	case "prompt" =>
		switch (args) {
		case "disclose" =>
			return prompt::DISCLOSE: command;
		case "delete" =>
			return prompt::DELETE: command;
		case "persist" =>
			return prompt::PERSIST: command;
		case "update" =>
			return prompt::UPDATE: command;
		case =>
			return errors::invalid;
		};
	case "unlock" =>
		return unlock;
	case "version" =>
		return version;
	case =>
		return errors::unsupported;
	};
};
