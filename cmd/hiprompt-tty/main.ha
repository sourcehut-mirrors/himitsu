use bufio;
use encoding::utf8;
use fmt;
use himitsu::query;
use io;
use memio;
use os;
use prompt;
use rt;
use strings;
use types;
use unix::signal;
use unix::tty;

type context = struct {
	tty: io::file,
	status: int,
	mode: prompt::mode,
	keys: []query::query,
};

export fn main() void = {
	const scan = bufio::newscanner(os::stdin, types::SIZE_MAX);
	defer bufio::finish(&scan);

	const tty = match (tty::open()) {
	case let file: io::file =>
		yield file;
	case let err: tty::error =>
		fatal("Error opening TTY:", tty::strerror(err));
	};

	signal::block(signal::sig::TTOU);
	let pgid = rt::getpgid(0)!;
	rt::ioctl(tty, 21520, &pgid)!; // TIOCSPGRP

	let ctx = context {
		tty = tty,
		status = 1,
		...
	};
	defer {
		for (let i = 0z; i < len(ctx.keys); i += 1) {
			query::finish(&ctx.keys[i]);
		};
		free(ctx.keys);
		io::close(ctx.tty)!;
	};

	const version = readline(&ctx, &scan, "version");
	if (version != "version") {
		fatal("Protocol error: expected version");
	};
	fmt::println("version 0.0.0")!;

	for (true) {
		const line = readline(&ctx, &scan, "command");
		const (cmd, args) = strings::cut(line, " ");
		switch (cmd) {
		case "key" =>
			const src = memio::fixed(strings::toutf8(args));
			const key = query::parse(&src)!;
			append(ctx.keys, key);
		case "password" =>
			if (args == "incorrect") {
				unlock(&ctx, true);
			};
		case "unlock" =>
			unlock(&ctx, false);
		case "prompt" =>
			switch (args) {
			case "disclose" =>
				ctx.mode = prompt::mode::DISCLOSE;
			case "delete" =>
				ctx.mode = prompt::mode::DELETE;
			};
			prompt(&ctx);
		};
	};
};

fn unlock(ctx: *context, again: bool) void = {
	if (again) {
		fmt::fprintln(ctx.tty, "Password incorrect.")!;
	} else {
		fmt::fprintln(ctx.tty, "An application wishes to unlock your Himitsu keyring.")!;
	};

	fmt::fprint(ctx.tty, "Enter password, or leave empty to cancel: ")!;

	const termios = tty::termios_query(ctx.tty)!;
	defer tty::termios_restore(&termios);
	tty::noecho(&termios)!;

	const scan = bufio::newscanner(ctx.tty, types::SIZE_MAX);
	defer bufio::finish(&scan);

	match (bufio::scan_line(&scan)) {
	case let line: const str =>
		if (line == "") {
			os::exit(1);
		};
		fmt::printfln("password {}", line)!;
	case =>
		fatal("Error reading user password");
	};
	fmt::fprintln(ctx.tty)!;
};

fn prompt(ctx: *context) void = {
	let mode = "decryption";
	if (ctx.mode == prompt::mode::DELETE) {
		mode = "deletion";
	};

	const scan = bufio::newscanner(ctx.tty, types::SIZE_MAX);
	defer bufio::finish(&scan);

	fmt::fprintfln(ctx.tty,
		"An application has requested {} of the following keys:",
		mode)!;
	for (let i = 0z; i < len(ctx.keys); i += 1) {
		fmt::fprintf(ctx.tty, "\t")!;
		query::unparse(ctx.tty, &ctx.keys[i])!;
	};

	fmt::fprint(ctx.tty, "Proceed? [y/N] ")!;

	const line = match (bufio::scan_line(&scan)) {
	case let line: const str =>
		yield line;
	case =>
		fatal("Error reading user password");
	};

	if (line == "y" || line == "Y") {
		ctx.status = 0;
		return;
	} else {
		os::exit(1);
	};
};

fn readline(ctx: *context, scan: *bufio::scanner, want: const str) const str = {
	match (bufio::scan_line(scan)) {
	case let line: const str =>
		return line;
	case let err: io::error =>
		fatal("I/O error:", io::strerror(err));
	case utf8::invalid =>
		fatal("Protocol error: invalid UTF-8 data from daemon");
	case io::EOF =>
		os::exit(ctx.status);
	};
};

// Exit prompter with an internal error
@noreturn fn fatal(args: fmt::formattable...) void = {
	fmt::errorln(args...)!;
	os::exit(127);
};
