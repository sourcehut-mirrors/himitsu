use fmt;
use io;
use shlex;
use memio;
use strings;

// Converts a Himitsu query into a string, including a newline, and writes it to
// the given I/O handle.
export fn unparse(sink: io::handle, q: *query) (size | io::error) = {
	let z = 0z;
	for (let i = 0z; i < len(q.items); i += 1) {
		const pair = &q.items[i];

		z += fmt::fprintf(sink, "{}", pair.key)?;

		if (pair.private) {
			z += fmt::fprintf(sink, "!")?;
		};
		if (pair.optional) {
			z += fmt::fprintf(sink, "?")?;
		};
		if (pair.value != "") {
			z += fmt::fprintf(sink, "=")?;
			z += shlex::quote(sink, pair.value)?;
		};

		if (i + 1 < len(q.items)) {
			z += fmt::fprint(sink, " ")?;
		};
	};
	z += fmt::fprintln(sink)?;
	return z;
};

// Converts a himitsu representation into a string. The string must bee freed
// by the caller.
export fn unparsestr(q: *query) (str | nomem) = {
	let buf = memio::dynamic();
	defer io::close(&buf)!;
	match (unparse(&buf, q)) {
	case size => void;
	case nomem =>
		return nomem;
	case io::error =>
		abort("unreachable");
	};
	return strings::dup(memio::string(&buf)!);
};
