use fmt;
use io;
use os;
use os::exec;
use secstore;

type prompt_mode = enum {
	DISCLOSE,
	AGENT,
};

// Executes the user's prompter to get permission to share a secret, returning
// true if the user consented and false otherwise.
export fn prompt(
	store: *secstore::secstore,
	entry: *secstore::entry,
	mode: prompt_mode,
) (bool | exec::error | io::error) = {
	// TODO: Configurable prompter
	const cmd = exec::cmd("hiprompt-gtk")?;
	const pipe = exec::pipe();
	exec::addfile(&cmd, os::stdin_file, pipe.0);
	const proc = exec::start(&cmd)?;
	io::close(pipe.0)!;

	fmt::fprintfln(pipe.1, "{} 0.0.0", switch (mode) {
	case prompt_mode::DISCLOSE =>
		yield "disclose";
	case prompt_mode::AGENT =>
		yield "agent";
	})!;

	fmt::fprint(pipe.1, "key ")?;
	secstore::write(store, pipe.1, entry, false)!;
	fmt::fprintln(pipe.1)?;
	io::close(pipe.1)!;

	const res = exec::wait(&proc)?;
	return exec::check(&res) is void;
};
