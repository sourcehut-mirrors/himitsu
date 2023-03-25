use bufio;
use dirs;
use errors;
use fmt;
use himitsu::query;
use io;
use net::unix;
use net;
use path;
use shlex;
use strings;
use strio;

// Query operations supported by Himitsu.
export type operation = enum uint {
	QUERY,
	ADD,
	DEL,
	QUIT,
};

// Flags for query operations.
export type flags = enum uint {
	// Requests decryption from the Himitsu daemon.
	DECRYPT = 1 << 0,
};

// All possible errors which may be returned by this module.
export type error = !(io::error | net::error | hierror);

export type hierror = !str;

// Converts an [[error]] to a human-friendly string.
export fn strerror(err: error) const str = {
	match (err) {
	case let err: hierror =>
		return err: const str;
	case let err: io::error =>
		return io::strerror(err);
	case let err: net::error =>
		if (err is errors::noentry || err is errors::refused) {
			return "Could not connect to himitsud (is it running?)";
		};
		return net::strerror(err);
	};
};

// Connects to the Himitsu socket, returning the connection's file descriptor.
export fn connect() (net::socket | error) = {
	let buf = path::init();
	// TODO: Bubble up dirs::runtime errors
	const sockpath = path::set(&buf, dirs::runtime()!, "himitsu")!;
	return unix::connect(sockpath)?;
};

export type keyiter = struct {
	conn: net::socket,
	buf: strio::stream,
};

// Executes a query using a Himitsu connection, returning an iterator which
// iterates through each key returned. The user must call [[next]] to retrieve
// the next key until all keys are returned, or risk a memory leak.
export fn query(
	conn: net::socket,
	op: operation,
	q: *query::query,
	flags: flags,
) (keyiter | error) = {
	const buf = bufio::dynamic(io::mode::WRITE);
	defer io::close(&buf)!;

	switch (op) {
	case operation::QUERY =>
		fmt::fprint(&buf, "query ")!;
	case operation::ADD =>
		fmt::fprint(&buf, "add ")!;
	case operation::DEL =>
		fmt::fprint(&buf, "del ")!;
	case operation::QUIT =>
		fmt::fprint(&buf, "quit ")!;
	};

	if (flags & flags::DECRYPT != 0) {
		fmt::fprint(&buf, "-d ")!;
	};

	query::unparse(&buf, q)!;

	io::writeall(conn, bufio::buffer(&buf))?;

	return keyiter {
		conn = conn,
		buf = strio::dynamic(),
	};
};

// Returns the next key from a key iterator, or void if no further keys are
// provided.
export fn next(iter: *keyiter) (const str | void | error) = {
	strio::reset(&iter.buf);
	match (bufio::scanline(iter.conn)?) {
	case let buf: []u8 =>
		io::writeall(&iter.buf, buf)!;
		free(buf);
	case io::EOF =>
		// XXX: This might be an error
		return;
	};
	const string = strio::string(&iter.buf);
	if (string == "end") {
		io::close(&iter.buf)!;
		return;
	};
	if (strings::hasprefix(string, "error ")) {
		// XXX: leaks
		return strings::sub(string, 6, strings::end): hierror: error;
	};
	if (strings::hasprefix(string, "key ")) {
		return strings::sub(string, 4, strings::end);
	};
	abort("himitsu returned unexpected response");
};
