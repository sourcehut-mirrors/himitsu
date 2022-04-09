use bufio;
use encoding::utf8;
use io;
use shlex;
use strings;

export type query = struct {
	items: []pair,
};

export type pair = struct {
	key: str,
	value: str,
	private: bool,
	optional: bool,
};

// Returned when the syntax of a query is not valid.
export type invalid = !void;

// Parses a query, returning its key/value pairs. The caller must pass the
// return value to [[query_finish]] when they are done with it.
export fn parse(in: io::handle) (query | invalid | io::error) = {
	const data = io::drain(in)?;
	const data = match (strings::try_fromutf8(data)) {
	case let data: str =>
		yield data;
	case utf8::invalid =>
		return invalid;
	};

	const items = match (shlex::split(data)) {
	case let items: []str =>
		yield items;
	case shlex::syntaxerr =>
		return invalid;
	};

	// XXX: Should do something about the case where the user specifies both
	// ? and !
	let query = query { ... };
	for (let i = 0z; i < len(items); i += 1) {
		const parts = strings::cut(items[i], "=");
		let key = parts.0, value = parts.1;
		let optional = false, private = false;
		if (strings::hassuffix(key, "!")) {
			private = true;
		};
		if (strings::hassuffix(key, "?")) {
			optional = true;
		};
		key = strings::trim(key, '?', '!');
		append(query.items, pair {
			key = key,
			value = value,
			private = private,
			optional = optional,
		});
	};
	return query;
};

export fn query_finish(q: *query) void = {
	for (let i = 0z; i < len(q.items); i += 1) {
		free(q.items[i].key);
	};
	free(q.items);
};

@test fn query() void = {
	const cases = [
		(`foo=bar bar=baz`, [
			("foo", "bar", false, false),
			("bar", "baz", false, false),
		]),
		(`foo? bar!=baz`, [
			("foo", "", false, true),
			("bar", "baz", true, false),
		]),
	];

	for (let i = 0z; i < len(cases); i += 1) {
		const expected = cases[i].1;
		const input = cases[i].0;
		const input = bufio::fixed(strings::toutf8(input),
			io::mode::READ);

		const result = parse(&input)!;
		defer query_finish(&result);

		assert(len(expected) == len(result.items));
		for (let j = 0z; j < len(result.items); j += 1) {
			const got = result.items[i];
			const expect = &expected[i];
			assert(got.key == expect.0);
			assert(got.value == expect.1);
			assert(got.private == expect.2);
			assert(got.optional == expect.3);
		};
	};
};
