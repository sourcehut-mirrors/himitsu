use dirs;
use fmt;
use format::ini;
use fs;
use io;
use os;
use path;
use shlex;
use strings;

// The himitsu configuration.
export type config = struct {
	prompter: []str,
};

// All possible errors returned by this module.
export type error = !(fs::error | io::error | ini::error);

// Converts an [[error]] to a human-friendly representation.
export fn strerror(err: error) const str = {
	match (err) {
	case let err: io::error =>
		return io::strerror(err);
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: ini::error =>
		return ini::strerror(err);
	};
};

// Loads the Himitsu configuration file. Pass the return value to [[finish]] to
// free associated resources.
export fn load() (config | error) = {
	let buf = path::init();
	path::set(&buf, dirs::config("himitsu"), "config.ini")!;

	const file = os::open(path::string(&buf))?;
	defer io::close(file)!;

	let conf = config { ... };

	const scanner = ini::scan(file);
	for (true) {
		const entry = match (ini::next(&scanner)?) {
		case let entry: ini::entry =>
			yield entry;
		case io::EOF =>
			break;
		};

		switch (entry.0) {
		case "himitsud" =>
			conf_himitsud(&conf, &entry);
		case =>
			yield;
		};
	};

	return conf;
};

fn conf_himitsud(conf: *config, entry: *ini::entry) void = {
	switch (entry.1) {
	case "prompter" =>
		match (shlex::split(entry.2)) {
		case shlex::syntaxerr =>
			// TODO: Bubble this up properly
			fmt::fatal("Config error: [himitsud]prompter: syntax error");
		case let items: []str =>
			conf.prompter = items;
		};
	case =>
		yield;
	};
};

// Frees resources associated with the Himitsu configuration.
export fn finish(conf: *config) void = {
	strings::freeall(conf.prompter);
};
