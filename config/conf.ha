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
	notify_reuse: str,
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
export fn load(configpath: str = "") (config | error | nomem) = {
	let buf = path::init()!;
	if (configpath == "") {
		path::set(&buf, dirs::config("himitsu"), "config.ini")!;
	} else {
		path::set(&buf, configpath)!;
	};

	const file = os::open(path::string(&buf))?;
	defer io::close(file)!;

	let conf = config { ... };

	const scanner = ini::scan(file);
	defer ini::finish(&scanner);
	for (let entry => ini::next(&scanner)) {
		// XXX: Error type (!format::ini::error | !nomem) is not
		// assignable to function result type (!config::error | !nomem |
		// config::config)
		match (entry) {
		case let entry: ini::entry =>
			switch (entry.0) {
			case "himitsud" =>
				conf_himitsud(&conf, &entry);
			case =>
				yield;
			};
		case nomem =>
			return nomem;
		case let e: ini::error =>
			return e;
		};
	};

	if (len(conf.prompter) == 0) {
		fmt::fatal("Config error: No prompter defined.");
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
	case "notify-reuse" =>
		conf.notify_reuse = strings::dup(entry.2)!;
	case =>
		yield;
	};
};

// Frees resources associated with the Himitsu configuration.
export fn finish(conf: *config) void = {
	strings::freeall(conf.prompter);
};
