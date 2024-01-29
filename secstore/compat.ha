use io;
use strings;
use shlex;
use himitsu::query;
use encoding::utf8;
use regex;

// Parses a query in compatibility mode, returning its key/value pairs. The
// caller must pass the return value to [[finish]] when they are done with it.
//
// The compatibility mode is required for the secstore to be operational,
// if it has invalid entries, because of a query format change.
fn compatquery_parse(in: io::handle) (query::query | query::error | io::error) = {
	let keyre: regex::regex = regex::compile(`^[-_A-Za-z]+$`)!;
	defer regex::finish(&keyre);

	const data = io::drain(in)?;
	const data = match (strings::fromutf8(data)) {
	case let data: str =>
		yield data;
	case utf8::invalid =>
		return query::invalid;
	};

	const items = match (shlex::split(data)) {
	case let items: []str =>
		yield items;
	case shlex::syntaxerr =>
		return query::invalid;
	};
	defer strings::freeall(items);

	// XXX: Should do something about the case where the user specifies both
	// ? and !
	let q = query::query { ... };
	let ok = false;
	defer if (!ok) query::finish(&q);

	for (let i = 0z; i < len(items); i += 1) {
		const (key, value) = strings::cut(items[i], "=");
		let optional = false, private = false;
		if (strings::hassuffix(key, "!")) {
			private = true;
		};
		if (strings::hassuffix(key, "?")) {
			optional = true;
		};
		key = strings::trim(key, '?', '!');
		if (!regex::test(&keyre, key)) {
			return query::invalid;
		};

		append(q.items, query::pair {
			key = strings::dup(key),
			value = strings::dup(value),
			private = private,
			optional = optional,
		});
	};

	ok = true;
	return q;
};

