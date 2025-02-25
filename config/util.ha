use himitsu::query;
use log;
use os;
use os::exec;
use wordexp;

// Runs the user's notify-reuse command, if configured.
export fn notify_reuse(conf: *config, query: *query::query) void = {
	if (conf.notify_reuse == "") {
		return;
	};

	match (os::exec::fork()!) {
	case exec::process =>
		return;
	case void => void;
	};

	const q = query::unparsestr(query)!;
	os::setenv("query", q)!;

	const args = match (wordexp::wordexp(conf.notify_reuse)) {
	case let args: []str =>
		yield args;
	case let err: wordexp::error =>
		log::fatalf("notify-reuse error: {}", wordexp::strerror(err));
	};

	const cmd = match (exec::cmd(args[0], args[1..]...)) {
	case let cmd: exec::command =>
		yield cmd;
	case let err: exec::error =>
		log::fatalf("notify-reuse error: {}", exec::strerror(err));
	};
	exec::exec(&cmd);
};
