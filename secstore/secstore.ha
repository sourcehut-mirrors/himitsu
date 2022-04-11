use bufio;
use bytes;
use crypto::keystore;
use crypto::random;
use crypto;
use encoding::base64;
use errors;
use dirs;
use fmt;
use io;
use os;
use path;
use strconv;
use strings;

def KEY_MEM: u32 = 100000;
def KEY_PASSES: u32 = 0;

// Initializes a new secstore using the provided passphrase. The caller should
// call [[close]] when they're done with it.
export fn create(passphrase: []u8) (secstore | error) = {
	let key: [32 + 16]u8 = [0...];
	defer bytes::zero(key);

	let salt: [16]u8 = [0...];
	random::buffer(salt);
	crypto::derivekey(key, salt, passphrase, KEY_MEM, KEY_PASSES)!;

	const verify = key[32..];
	const key = keystore::newkey(key[..32], "secstore")!;
	const dir = strings::dup(dirs::data("himitsu"));

	let buf = path::init();
	path::set(&buf, dir, "key")!;
	const keyfile = os::create(path::string(&buf), 0o600)?;
	defer io::close(keyfile);
	let wbuf: [os::BUFSIZ]u8 = [0...];
	const keyfile = &bufio::buffered(keyfile, [], wbuf);
	defer io::close(keyfile);

	fmt::fprintf(keyfile, "argon2i:{}:{}:", KEY_MEM, KEY_PASSES)?;
	base64::encode(keyfile, &base64::std_encoding, salt)?;
	fmt::fprintf(keyfile, ":")?;
	base64::encode(keyfile, &base64::std_encoding, verify)?;
	fmt::fprintln(keyfile)?;

	path::set(&buf, dir, "index")!;
	const index = os::create(path::string(&buf), 0o600)?;
	io::close(index);

	return secstore {
		key = key,
		dir = dir,
		entries = [],
	};
};

// Opens the secstore using the given passphrase and returns a state object. The
// caller should call [[close]] when they're done with it.
export fn open(passphrase: []u8) (secstore | error) = {
	const dir = strings::dup(dirs::data("himitsu"));
	let buf = path::init();
	path::set(&buf, dir, "key")!;

	const input = os::open(path::string(&buf))?;
	defer io::close(input);
	let rbuf: [os::BUFSIZ]u8 = [0...];
	const input = &bufio::buffered(input, rbuf, []);

	const keydata = match (bufio::scanline(input)) {
	case let buf: []u8 =>
		yield strings::fromutf8(buf);
	case io::EOF =>
		return badstore;
	};
	defer free(keydata);
	const items = strings::split(keydata, ":");
	defer free(items);
	if (len(items) != 5) {
		return badstore;
	};

	if (items[0] != "argon2i") {
		return badstore;
	};
	const mem = match (strconv::stou32(items[1])) {
	case let u: u32 =>
		yield u;
	case =>
		return badstore;
	};
	const passes = match (strconv::stou32(items[2])) {
	case let u: u32 =>
		yield u;
	case =>
		return badstore;
	};

	const salt = match (base64::decodestr(&base64::std_encoding, items[3])) {
	case let buf: []u8 =>
		yield buf;
	case errors::invalid =>
		return badstore;
	};
	defer free(salt);

	const verify = match (base64::decodestr(&base64::std_encoding, items[4])) {
	case let buf: []u8 =>
		yield buf;
	case errors::invalid =>
		return badstore;
	};
	defer free(verify);

	if (len(salt) != 16 || len(verify) != 16) {
		return badstore;
	};

	let key: [32 + 16]u8 = [0...];
	defer bytes::zero(key);

	crypto::derivekey(key, salt, passphrase, mem, passes)!;

	if (!crypto::compare(key[32..], verify)) {
		return badpass;
	};

	const key = keystore::newkey(key[..32], "secstore")!;
	return secstore {
		key = key,
		dir = dir,
		// TODO: Load entries from index
		entries = [],
	};
};

// Closes the secstore, freeing any associated resources.
export fn close(store: *secstore) void = {
	keystore::destroy(store.key);
	free(store.dir);
};
