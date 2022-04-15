use fmt;
use io;
use shlex;
use uuid;

// Serializes a secstore entry to the given I/O handle, returning the number of
// bytes written. The entry is written in its plaintext form, with secret keys
// hidden.
export fn writeplain(sink: io::handle, ent: *entry) (void | io::error) = {
	// TODO: https://todo.sr.ht/~sircmpwn/hare/619
	for (let i = 0z; i < len(ent.pairs); i += 1) {
		const pair = &ent.pairs[i];
		shlex::quote(sink, pair.key)?;
		match (pair.value) {
		case let val: str =>
			fmt::fprint(sink, "=")?;
			shlex::quote(sink, val)?;
		case uuid::uuid =>
			fmt::fprint(sink, "!")?;
		};
		if (i + 1 < len(ent.pairs)) {
			fmt::fprint(sink, " ")?;
		};
	};
};
