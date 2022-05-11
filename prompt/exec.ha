use fmt;
use io;
use os::exec;
use os;
use secstore;

// Prompts the user to disclose an encrypted key.
export fn disclose(
	cmd: str,
	store: *secstore::secstore,
	entry: *secstore::entry,
) (bool | exec::error | io::error) = {
	const cmd = exec::cmd(cmd)?;
	const pipe = exec::pipe();
	exec::addfile(&cmd, os::stdin_file, pipe.0);
	const proc = exec::start(&cmd)?;
	io::close(pipe.0)!;

	fmt::fprintfln(pipe.1, "disclose 0.0.0")?;
	fmt::fprint(pipe.1, "key ")?;
	secstore::write(store, pipe.1, entry, false)!;
	fmt::fprintln(pipe.1)?;
	io::close(pipe.1)!;

	const res = exec::wait(&proc)?;
	return exec::check(&res) is void;
};
