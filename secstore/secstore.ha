use bufio;
use bytes;
use crypto::argon2;
use crypto::keystore;
use crypto::random;
use crypto;
use dirs;
use encoding::base64;
use errors;
use fmt;
use fs;
use himitsu::query;
use io;
use os;
use path;
use shlex;
use strconv;
use strings;
use uuid;

def KEY_MEM: u32 = 100000;
def KEY_PASSES: u32 = 0;

// Initializes a new secstore using the provided passphrase. The caller should
// call [[close]] when they're done with it.
export fn create(passphrase: []u8) (secstore | error) = {
	let key: [32 + 16]u8 = [0...];
	defer bytes::zero(key);

	let salt: [16]u8 = [0...];
	random::buffer(salt);
	// TODO: Switch to argon2id by default
	const config = argon2::config {
		mem = KEY_MEM,
		parallel = 1,
		passes = KEY_PASSES + 3,
		version = argon2::VERSION,
		...
	};
	argon2::argon2i(key, passphrase, salt, &config)!;

	const verify = key[32..];
	const key = keystore::newkey(key[..32], "secstore")!;
	const dir = strings::dup(dirs::data("himitsu"));

	let buf = path::init();
	path::set(&buf, dir, "key")!;
	const keyfile = os::create(path::string(&buf), 0o600)?;
	defer io::close(keyfile)!;
	let wbuf: [os::BUFSIZ]u8 = [0...];
	const keyfile = &bufio::buffered(keyfile, [], wbuf);
	defer io::close(keyfile)!;

	fmt::fprintf(keyfile, "argon2i:{}:{}:", KEY_MEM, KEY_PASSES)?;
	base64::encode(keyfile, &base64::std_encoding, salt)?;
	fmt::fprintf(keyfile, ":")?;
	base64::encode(keyfile, &base64::std_encoding, verify)?;
	fmt::fprintln(keyfile)?;

	path::set(&buf, dir, "index")!;
	const index = os::create(path::string(&buf), 0o600)?;

	return secstore {
		key = key,
		dir = dir,
		index = index,
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
	defer io::close(input)!;
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

	// TODO: Switch to argon2id by default
	const config = argon2::config {
		mem = mem,
		parallel = 1,
		passes = passes + 3,
		version = argon2::VERSION,
		...
	};
	argon2::argon2i(key, passphrase, salt, &config)!;

	if (!crypto::compare(key[32..], verify)) {
		return badpass;
	};

	const key = keystore::newkey(key[..32], "secstore")!;

	path::set(&buf, dir, "index")!;
	const index = os::open(path::string(&buf),
		fs::flags::RDWR | fs::flags::CLOEXEC | fs::flags::NOCTTY)?;

	const store = secstore {
		key = key,
		dir = dir,
		index = index,
		entries = [],
	};
	match (load_index(&store)) {
	case void => yield;
	case let err: io::error =>
		return err;
	case errors::invalid =>
		return badstore;
	};
	return store;
};

// Closes the secstore, freeing any associated resources.
export fn close(store: *secstore) void = {
	io::close(store.index)!;
	keystore::destroy(store.key);
	free(store.dir);
};

// Adds an item to the keystore. The provided query must not have any missing
// values.
export fn add(store: *secstore, q: *query::query) *entry = {
	// TODO: Better error handling
	let pairs: []pair = [];
	for (let i = 0z; i < len(q.items); i += 1) {
		const item = q.items[i];
		assert(item.value != "", "Invalid query submitted to secstore::add");
		const val = if (item.private) {
			yield add_secret(store, item.value);
		} else {
			yield strings::dup(item.value);
		};
		append(pairs, pair {
			key = strings::dup(item.key),
			value = val,
		});
	};
	append(store.entries, entry {
		pairs = pairs,
	});
	let entry = &store.entries[len(store.entries) - 1];
	add_index(store, entry);
	return entry;
};

// Encrypts and stores a secret value, returning its assigned UUID.
fn add_secret(store: *secstore, val: str) uuid::uuid = {
	const id = uuid::generate();
	const idstr = uuid::encodestr(id);

	let buf = path::init();
	path::set(&buf, store.dir, idstr)!;

	const file = os::create(path::string(&buf), 0o600)!;
	defer io::close(file)!;

	let key: [32]u8 = [0...];
	defer bytes::zero(key);
	keystore::read(store.key, key);

	let nonce: crypto::nonce = [0...];
	random::buffer(nonce);
	let ciphertext = strings::toutf8(strings::dup(val));
	defer free(ciphertext);
	const box = crypto::encrypt(&key, &nonce, ciphertext);
	io::write(file, box.0)!;
	io::write(file, box.1)!;
	io::write(file, box.2)!;
	return id;
};

// Encrypts and writes an entry to the index.
fn add_index(store: *secstore, entry: *entry) void = {
	let buf = bufio::dynamic(io::mode::WRITE);
	defer io::close(&buf)!;

	for (let i = 0z; i < len(entry.pairs); i += 1) {
		const pair = &entry.pairs[i];
		shlex::quote(&buf, pair.key)!;

		match (pair.value) {
		case let uuid: uuid::uuid =>
			fmt::fprint(&buf, "!=")!;
			uuid::encode(&buf, uuid)!;
		case let val: str =>
			fmt::fprint(&buf, "=")!;
			shlex::quote(&buf, val)!;
		};

		if (i + 1 < len(entry.pairs)) {
			fmt::fprint(&buf, " ")!;
		};
	};

	const buf = bufio::buffer(&buf);

	let key: [32]u8 = [0...];
	defer bytes::zero(key);
	keystore::read(store.key, key);

	let nonce: crypto::nonce = [0...];
	random::buffer(nonce);

	const box = crypto::encrypt(&key, &nonce, buf);
	const enc = base64::newencoder(&base64::std_encoding, store.index);
	io::write(&enc, box.0)!;
	io::write(&enc, box.1)!;
	io::write(&enc, box.2)!;
	io::close(&enc)!;
	fmt::fprintln(store.index)!;
};

// Decrypts and loads keystore entries from the index.
fn load_index(store: *secstore) (void | io::error | errors::invalid) = {
	let key: [32]u8 = [0...];
	defer bytes::zero(key);
	keystore::read(store.key, key);

	for (true) {
		const line = match (bufio::scanline(store.index)?) {
		case let line: []u8 =>
			yield line;
		case io::EOF =>
			break;
		};
		defer free(line);

		const buf = bufio::fixed(line, io::mode::READ);
		const dec = base64::newdecoder(&base64::std_encoding, &buf);

		let mac: crypto::mac = [0...];
		let nonce: crypto::nonce = [0...];
		io::readall(&dec, mac)?;
		io::readall(&dec, nonce)?;
		let ciphertext = io::drain(&dec)?;
		defer {
			bytes::zero(ciphertext);
			free(ciphertext);
		};

		let box: crypto::box = (mac, nonce, ciphertext);
		const plaintext = crypto::decrypt(&key, &box)?;
		const buf = bufio::fixed(plaintext, io::mode::READ);
		const q = query::parse(&buf)!;
		defer query::finish(&q);

		let pairs: []pair = [];
		for (let i = 0z; i < len(q.items); i += 1) {
			const item = q.items[i];
			const val = if (item.private) {
				yield uuid::decodestr(item.value)!;
			} else {
				yield strings::dup(item.value);
			};
			append(pairs, pair {
				key = strings::dup(item.key),
				value = val,
			});
		};
		append(store.entries, entry {
			pairs = pairs,
		});
	};
};
