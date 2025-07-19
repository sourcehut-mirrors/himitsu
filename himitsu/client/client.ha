use bufio;
use dirs;
use errors;
use fmt;
use fs;
use himitsu::query;
use himitsu::remember;
use io;
use net::unix;
use net;
use path;
use shlex;
use strconv;
use strings;
use memio;
use encoding::utf8;

// Query operations supported by Himitsu.
export type operation = enum uint {
	QUERY,
	ADD,
	DEL,
	UPDATE,
	QUIT,
};

// Secret store state.
export type state = enum {
	// Public entry keys decrypted and master key is stored in memory.
	UNLOCKED,

	// Public entry keys decrypted but master key is unloaded.
	SOFT_LOCKED,

	// Entries and master keys are unloaded.
	HARD_LOCKED,
};

// Flags for query operations.
export type flags = enum uint {
	// Requests decryption from the Himitsu daemon.
	DECRYPT = 1 << 0,

	// Enable strict query mode
	STRICT = 1 << 1,
};

// Additional options
export type options = struct {
	// Desired remember options
	remember: []remember::option,
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
	let buf = path::init()!;
	const runtimedir = match (dirs::runtime()) {
	case let r: str =>
		yield r;
	case fs::error =>
		return "XDG_RUNTIME_DIR unset or incorrectly set up.": hierror;
	};
	const sockpath = path::set(&buf, runtimedir, "himitsu")!;
	return unix::connect(sockpath)?;
};

export fn parse_remembercmd(cmd: str) (remember::option | errors::invalid) = {
	const (method, arg) = strings::cut(cmd, " ");
	switch (method) {
	case "session" =>
		return remember::session;
	case "skip" =>
		return remember::skip;
	case "refuse" =>
		return remember::refuse;
	case "timeout" =>
		match (strconv::stou32(arg)) {
		case let t: u32 =>
			return t: remember::timeout;
		case strconv::error =>
			return errors::invalid;
		};
	case =>
		return errors::invalid;
	};
};

export type keyiter = struct {
	conn: net::socket,
	buf: memio::stream,
};

// Executes a query using a Himitsu connection, returning an iterator which
// iterates through each key returned. The user must call [[next]] to retrieve
// the next key until all keys are returned, or risk a memory leak.
export fn query(
	conn: net::socket,
	op: operation,
	q: *query::query,
	flags: flags,
	opts: (void | options) = void,
) (keyiter | error) = {
	const buf = memio::dynamic();
	defer io::close(&buf)!;

	switch (op) {
	case operation::QUERY =>
		fmt::fprint(&buf, "query ")?;
	case operation::ADD =>
		fmt::fprint(&buf, "add ")?;
	case operation::DEL =>
		fmt::fprint(&buf, "del ")?;
	case operation::UPDATE =>
		abort("use the update function");
	case operation::QUIT =>
		fmt::fprint(&buf, "quit ")?;
	};

	if (flags & flags::DECRYPT != 0) {
		fmt::fprint(&buf, "-d ")?;
	};

	if (flags & flags::STRICT != 0) {
		fmt::fprint(&buf, "-s ")?;
	};

	write_remopts(&buf, opts)?;

	query::unparse(&buf, q)?;

	io::writeall(conn, memio::buffer(&buf))?;

	return keyiter {
		conn = conn,
		buf = memio::dynamic(),
	};
};

// Executes an update operation. All keys matched by 'q' will be changed
// according to `updates`. Only pairs in `updates` will be considered. If a pair
// doesn't have a value, it will be deleted. Otherwise the value will be
// changed.
// Returns an iterator that iterates through each changed key returned. The user
// must call [[next]] to retrieve the next key until all keys are returned, or
// risk a memory leak.
export fn update(
	conn: net::socket,
	q: *query::query,
	updates: *query::query,
	flags: flags,
) (keyiter | error) = {
	const buf = memio::dynamic();
	defer io::close(&buf)!;

	fmt::fprint(&buf, "update ")?;
	if (flags & flags::STRICT != 0) {
		fmt::fprint(&buf, "-s ")?;
	};
	query::unparse(&buf, q)?;

	io::writeall(conn, memio::buffer(&buf))?;

	let lbuf = match (bufio::read_line(conn)?) {
	case let lbuf: []u8 =>
		yield lbuf;
	case io::EOF =>
		return "Internal error": hierror;
	};
	defer free(lbuf);

	const line = match (strings::fromutf8(lbuf)) {
	case let s: str =>
		yield s;
	case utf8::invalid =>
		return errors::invalid: io::error;
	};

	if (strings::hasprefix(line, "error ")) {
		// TODO: leaks
		return strings::dup(strings::sub(line, 6)): hierror: error;
	};
	if (line != "update") {
		return "Internal error": hierror;
	};

	memio::reset(&buf);
	fmt::fprint(&buf, "set ")?;
	query::unparse(&buf, updates)?;

	io::writeall(conn, memio::buffer(&buf))?;

	return keyiter {
		conn = conn,
		buf = memio::dynamic(),
	};
};

fn write_remopts(
	buf: io::handle,
	opts: (options | void)
) (void | error) = {
	let opts: []remember::option = match (opts) {
	case void =>
		return;
	case let o: options =>
		yield o.remember;
	};

	if (len(opts) == 0) {
		return;
	};

	fmt::fprint(buf, "-r ")?;
	let first = true;
	for (let r .. opts) {
		if (!first) fmt::fprint(buf, ",")? else first = false;

		match (r) {
		case let t: remember::timeout =>
			fmt::fprintf(buf, "{}", t)?;
		case let p: remember::option =>
			fmt::fprint(buf, remember::stroption(p))?;
		};
	};

	fmt::fprint(buf, " ")?;
};

// Returns the next key from a key iterator, or void if no further keys are
// provided.
export fn next(iter: *keyiter) (query::query | done | error) = {
	memio::reset(&iter.buf);
	match (bufio::read_line(iter.conn)?) {
	case let buf: []u8 =>
		defer free(buf);
		io::writeall(&iter.buf, buf)?;
	case io::EOF =>
		// XXX: This might be an error
		return done;
	};
	const string = match (memio::string(&iter.buf)) {
	case let s: str =>
		yield s;
	case utf8::invalid =>
		return errors::invalid: io::error;
	};
	if (string == "end") {
		io::close(&iter.buf)!;
		return done;
	};
	if (strings::hasprefix(string, "error ")) {
		// XXX: leaks
		return strings::sub(string, 6, strings::end): hierror: error;
	};
	if (strings::hasprefix(string, "key ")) {
		const key = strings::sub(string, 4, strings::end);
		match (query::parse_str(key)) {
		case let q: query::query =>
			return q;
		case query::error =>
			// happens when querying invalid keys that have been
			// stored before the introduction of new entry
			// restrictions.
			fmt::errorfln("himitsu returned an invalid key: {}",
				strings::sub(string, 4, strings::end))!;
			abort();
		};
	};
	abort("himitsu returned an unexpected response");
};

// Persist remembers consent for given query, so that future calls may decrypt
// secret data without prompting the user, if the store is unlocked.
export fn persist(
	conn: net::socket,
	q: *query::query,
	flags: flags = 0,
	opts: (void | options) = void,
) (remember::option | error) = {
	const buf = memio::dynamic();
	defer io::close(&buf)!;

	fmt::fprint(&buf, "persist ")?;

	if (flags & flags::STRICT != 0) {
		fmt::fprint(&buf, "-s ")?;
	};

	write_remopts(&buf, opts)?;
	query::unparse(&buf, q)?;
	io::writeall(conn, memio::buffer(&buf))?;

	let buf = match (bufio::read_line(conn)?) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		return "Internal error": hierror;
	};
	defer free(buf);

	const line = match (strings::fromutf8(buf)) {
	case let s: str =>
		yield s;
	case utf8::invalid =>
		return errors::invalid: io::error;
	};

	if (strings::hasprefix(line, "error ")) {
		// TODO: leaks
		return strings::dup(strings::sub(line, 6)): hierror: error;
	};
	if (strings::hasprefix(line, "persist ")) {
		const (_, args) = strings::cut(line, " ");
		match (parse_remembercmd(args)) {
		case let r: remember::option =>
			return r;
		case errors::invalid =>
			return "Internal error": hierror;
		};
	};

	return "Internal error": hierror;
};

// Locks the keyring. If 'soft' is true, it will soft lock rather than hard
// lock.
export fn lock(conn: net::socket, soft: bool = false) (void | error) = {
	const buf = memio::dynamic();
	defer io::close(&buf)!;

	fmt::fprint(&buf, "lock")?;

	if (soft) {
		fmt::fprint(&buf, " -s")?;
	};
	fmt::fprintln(&buf)?;
	io::writeall(conn, memio::buffer(&buf))?;

	let buf = match (bufio::read_line(conn)?) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		return "Internal error": hierror;
	};
	defer free(buf);

	const line = match (strings::fromutf8(buf)) {
	case let s: str =>
		yield s;
	case utf8::invalid =>
		return errors::invalid: io::error;
	};

	if (strings::hasprefix(line, "error ")) {
		// TODO: leaks
		return strings::dup(strings::sub(line, 6)): hierror: error;
	};

	if (line != "locked") {
		return "Internal error": hierror;
	};
};

// Request secret store state.
export fn get_state(conn: net::socket) (state | error) = {
	fmt::fprintln(conn, "status")?;

	let buf = match (bufio::read_line(conn)?) {
	case let buf: []u8 =>
		yield buf;
	case io::EOF =>
		return "Internal error": hierror;
	};
	defer free(buf);

	const line = match (strings::fromutf8(buf)) {
	case let s: str =>
		yield s;
	case utf8::invalid =>
		return errors::invalid: io::error;
	};

	if (strings::hasprefix(line, "error ")) {
		// TODO: leaks
		return strings::dup(strings::sub(line, 6)): hierror: error;
	};

	if (!strings::hasprefix(line, "status ")) {
		return "Internal error": hierror;
	};

	let (_, args) = strings::cut(line, " ");
	switch (args) {
	case "unlocked" =>
		return state::UNLOCKED;
	case "soft_locked" =>
		return state::SOFT_LOCKED;
	case "hard_locked" =>
		return state::HARD_LOCKED;
	case =>
		return "Internal error": hierror;
	};
};

// String representation of 's'.
export fn statestr(s: state) str = {
	switch (s) {
	case state::UNLOCKED =>
		return "unlocked";
	case state::SOFT_LOCKED =>
		return "soft_locked";
	case state::HARD_LOCKED =>
		return "hard_locked";
	};
};
