use bytes;
use memio;
use encoding::utf8;
use io;
use regex;
use shlex;
use sort::cmp;
use sort::{sort};
use strings;
use fmt;

let keyre: regex::regex = regex::regex { ... };

@init fn init() void = {
	keyre = regex::compile(`^[-_A-Za-z]+$`)!;
};

@fini fn fini() void = {
	regex::finish(&keyre);
};

// A parsed Himitsu query.
export type query = struct {
	items: []pair,
};

// A key/value pair in a Himitsu key.
export type pair = struct {
	key: str,
	value: str,
	private: bool,
	optional: bool,
};

// Returned when the syntax of a query is not valid.
export type invalid = !void;

// Returned when keys are not unique within query.
export type dupkeys = !void;

// An error which may be returned form a query function
export type error = !(invalid | dupkeys);

// Returns the string representation of a query error.
export fn strerror(err: error) str = {
	match (err) {
	case invalid =>
		return "Invalid query";
	case dupkeys =>
		return "A query must not contain duplicate keys";
	};
};

// Checks whether 'q' has no items.
export fn is_empty(q: *query) bool = len(q.items) == 0;

// Parses a query, returning its key/value pairs. The caller must pass the
// return value to [[finish]] when they are done with it.
export fn parse(in: io::handle) (query | error | io::error) = {
	const data = io::drain(in)?;
	const data = match (strings::fromutf8(data)) {
	case let data: str =>
		yield data;
	case utf8::invalid =>
		return invalid;
	};
	return parse_str(data);
};

// Parses a query from a string, returning its key/value pairs. The caller must
// pass the return value to [[finish]] when they are done with it.
export fn parse_str(in: str) (query | error) = {
	const items = match (shlex::split(in)) {
	case let items: []str =>
		yield items;
	case shlex::syntaxerr =>
		return invalid;
	};
	defer strings::freeall(items);
	return parse_items(items);
};

// Parses a list of key/value pairs which has already been split with shlex (or
// a shell, for example when parsing a query from argv).
export fn parse_items(items: []str) (query | error) = {
	// XXX: Should do something about the case where the user specifies both
	// ? and !
	let query = query { ... };
	let ok = false;
	defer if (!ok) finish(&query);

	let keys: []str = [];
	defer free(keys);

	for (let item .. items) {
		const (key, value) = strings::cut(item, "=");
		let optional = false, private = false;
		if (strings::hassuffix(key, "!")) {
			private = true;
		};
		if (strings::hassuffix(key, "?")) {
			optional = true;
		};
		key = strings::trim(key, '?', '!');
		if (!regex::test(&keyre, key)) {
			return invalid;
		};

		append(query.items, pair {
			key = strings::dup(key),
			value = strings::dup(value),
			private = private,
			optional = optional,
		});
		append(keys, key);
	};

	if (len(query.items) == 0) {
		ok = true;
		return query;
	};

	// check dupes
	sort(keys, size(str), &cmp::strs);
	let prev = keys[0];
	for (let i = 1z; i < len(keys); i += 1) {
		if (prev == keys[i]) {
			return dupkeys;
		};
		prev = keys[i];
	};

	ok = true;
	return query;
};

// Duplicates a query, but only keeps values of public key/value pairs. The
// caller must pass the return value to [[finish]] after use.
export fn dup_pub(q: *query) query = {
	let query = query { ... };
	for (let p .. q.items) {
		p.key = strings::dup(p.key);
		p.value = if (p.private) "" else strings::dup(p.value);

		append(query.items, p);
	};
	return query;
};

// Frees resources associated with this query.
export fn finish(q: *query) void = {
	for (let item .. q.items) {
		free(item.key);
		if (item.private) {
			bytes::zero(strings::toutf8(item.value));
		};
		free(item.value);
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
		const input = memio::fixed(strings::toutf8(input));

		const result = parse(&input)!;
		defer finish(&result);

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

	const errcases = [
		`foo=bar foo=bar`,
		`foo=bar foo=baz`,
		`foo=bar foo!=baz`,
		`foo=bar bar=bay foo=baz`,
	];
	for (let err .. errcases) {
		const input = memio::fixed(strings::toutf8(err));
		assert(parse(&input) is dupkeys);
	};
};
