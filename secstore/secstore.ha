use bufio;
use bytes;
use crypto::keystore;
use crypto::random;
use crypto;
use encoding::base64;
use dirs;
use fmt;
use io;
use os;
use path;
use strings;

def KEY_MEM: u32 = 100000;
def KEY_PASSES: u32 = 0;

// Initializes a new secstore based on the provided passphrase.
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
	const b64 = &base64::new_encoder(&base64::std_encoding, keyfile);
	io::writeall(b64, salt)?;
	io::close(b64);

	fmt::fprintf(keyfile, ":")?;
	const b64 = &base64::new_encoder(&base64::std_encoding, keyfile);
	io::writeall(b64, verify)?;
	fmt::fprintln(keyfile)?;

	return secstore {
		key = key,
		dir = dir,
	};
};

// Opens the secstore using the given passphrase and returns a state object. The
// caller should call [[close]] when they're done with it.
export fn open(passphrase: []u8) (secstore | error) = {
	abort(); // TODO
};

// Returns true if this user has already initialized a secstore.
export fn exists() bool = {
	let buf = path::init();
	path::set(&buf, dirs::data("himitsu"), "key")!;
	const path = path::string(&buf);
	match (os::access(path, os::amode::R_OK | os::amode::W_OK)) {
	case let b: bool =>
		return b;
	case =>
		return false;
	};
};

// Closes the secstore, freeing any associated resources.
export fn close(store: *secstore) void = {
	keystore::destroy(store.key);
	free(store.dir);
};
