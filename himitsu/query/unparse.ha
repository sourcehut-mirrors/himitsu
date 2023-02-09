use fmt;
use io;
use shlex;

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
