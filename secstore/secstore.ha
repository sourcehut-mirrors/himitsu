use bufio;
use bytes;
use crypto::argon2;
use crypto::argon2bug;
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

type keyversion = enum u8 {
	// Buggy argon2 key
	V0 = 0,

	// argon2 key encrypted master key
	V1 = 1,
};

// Initializes a new secstore using the provided passphrase. The caller should
// call [[close]] when they're done with it.
export fn create(passphrase: []u8) (secstore | error) = {
	let dir = strings::dup(dirs::data("himitsu"));
	return createat(passphrase, dir);
};

// Deletes the Himitsu secstore directory. This is not reversible and will
// result in the loss of all keys in the secstore.
export fn remove() (void | fs::error) = {
	let dir = dirs::data("himitsu");
	return fs::rmdirall(os::cwd, dir);
};

fn createat(passphrase: []u8, dir: const str) (secstore | error) = {
	let key: [32 + 16]u8 = [0...];
	defer bytes::zero(key);

	let salt: [16]u8 = [0...];
	random::buffer(salt);
	const config = argon2::conf {
		mem = KEY_MEM,
		parallel = 1,
		passes = KEY_PASSES + 3,
		version = argon2::VERSION,
		...
	};
	argon2::argon2id(key, passphrase, salt, &config)!;

	const verify = key[32..];

	let buf = path::init()!;
	path::set(&buf, dir, "key")!;
	const keyfile = os::create(path::string(&buf), 0o600)?;
	defer io::close(keyfile)!;
	let wbuf: [os::BUFSIZ]u8 = [0...];
	const keyfile = &bufio::buffered(keyfile, [], wbuf);
	defer io::close(keyfile)!;

	fmt::fprintf(keyfile, "argon2id:{}:{}:", KEY_MEM, KEY_PASSES)?;
	base64::encode(keyfile, &base64::std_encoding, salt)?;
	fmt::fprintf(keyfile, ":")?;
	base64::encode(keyfile, &base64::std_encoding, verify)?;
	fmt::fprintf(keyfile, ":{}:", keyversion::V1: u8)?;

	let masterkeybuf: [32]u8 = [0...];
	random::buffer(masterkeybuf);
	defer bytes::zero(masterkeybuf);
	let masterkey = keystore::newkey(masterkeybuf, "secstoreinit")!;

	let mkkey = keystore::newkey(key[..32], "masterkeykey")!;
	defer keystore::destroy(mkkey);

	let enc = base64::newencoder(&base64::std_encoding, keyfile);
	secbox(&enc, mkkey, masterkeybuf)!;
	io::close(&enc)!;

	path::set(&buf, dir, "index")!;
	const index = os::create(path::string(&buf), 0o600)?;

	return secstore {
		key = masterkey,
		state = state::UNLOCKED,
		dir = dir,
		index = index,
		entries = [],
	};
};

// Generates a new master key and re-encrypts the secstore.
export fn reencrypt(passphrase: []u8) (void | error) = {
	let oldstore = openat(strings::dup(dirs::data("himitsu")))?;
	unlock(&oldstore, passphrase)?;
	let closed = false;
	defer if (!closed) close(&oldstore);

	let store = createat(passphrase, strings::dup(dirs::data("himitsu.new")))!;
	defer if (!closed) close(&store);

	const q = query::query { ... };
	const iter = query(&oldstore, &q);
	for (true) {
		const item = match (next(&oldstore, &iter)) {
		case let item: *entry =>
			let buf = bufio::dynamic(io::mode::RDWR);
			defer io::close(&buf)!;
			write(&oldstore, &buf, item, true)!;

			io::seek(&buf, 0, io::whence::SET)!;

			let iq = query::parse(&buf)!;
			defer query::finish(&iq);
			add(&store, &iq)!;
			yield item;
		case void =>
			break;
		};
	};

	close(&oldstore);
	close(&store);
	closed = true;

	let dir = strings::dup(dirs::data("himitsu"));
	defer free(dir);
	let dirold = strings::dup(dirs::data("himitsu.old"));
	defer free(dirold);

	match (os::rename(dir, dirold)) {
	case let e: fs::error =>
		fmt::fatalf("Moving himitsu to himitsu.old failed: {}",
			fs::strerror(e));
	case =>
		yield;
	};

	let dirnew = strings::dup(dirs::data("himitsu.new"));
	defer free(dirnew);
	match (os::rename(dirnew, dir)) {
	case let e: fs::error =>
		fmt::fatalf("Moving himitsu.new to himitsu failed: {}",
			fs::strerror(e));
	case =>
		yield;
	};
};

// Encrypts msg and writes it to sink
fn secbox(
	sink: io::handle,
	key: (keystore::key | []u8),
	msg: []u8
) (void | io::error) = {
	let keybuf: [32]u8 = [0...];
	defer bytes::zero(keybuf);
	match (key) {
	case let key: keystore::key =>
		keystore::read(key, keybuf);
	case let key: []u8 =>
		keybuf[..] = key[..];
	};

	let nonce: crypto::nonce = [0...];
	random::buffer(nonce);

	const box = crypto::encrypt(&keybuf, &nonce, msg);

	io::write(sink, box.0)?;
	io::write(sink, box.1)?;
	io::write(sink, box.2)?;
};

// Reads the ciphertext created with [[secbox]] from 'src' and returns the
// plaintext. The user must free the plaintext after use.
fn secunbox(src: io::handle, key: (keystore::key | []u8)) ([]u8 | io::error) = {
	let keybuf: [32]u8 = [0...];
	defer bytes::zero(keybuf);
	match (key) {
	case let key: keystore::key =>
		keystore::read(key, keybuf);
	case let key: []u8 =>
		keybuf[..] = key[..];
	};

	let mac: crypto::mac = [0...];
	let nonce: crypto::nonce = [0...];
	io::readall(src, mac)?;
	io::readall(src, nonce)?;
	let ciphertext = io::drain(src)?;
	let box: crypto::box = (mac, nonce, ciphertext);
	return crypto::decrypt(&keybuf, &box)?;
};

// Opens the secstore. The caller should call [[unlock]] to decrypt it, and
// [[close]] when they're done with it.
export fn open() (secstore | error) = {
	let dir = strings::dup(dirs::data("himitsu"));
	return openat(dir);
};

fn openat(dir: str) (secstore | error) = {
	let buf = path::init()!;
	path::set(&buf, dir, "index")!;

	const index = os::open(path::string(&buf), fs::flag::RDWR)?;
	return secstore {
		key = void,
		state = state::HARD_LOCKED,
		dir = dir,
		index = index,
		entries = [],
	};
};

// Unlocks the keystore using the given passphrase.
export fn unlock(store: *secstore, passphrase: []u8) (void | error) = {
	let buf = path::init()!;
	path::set(&buf, store.dir, "key")!;

	const input = os::open(path::string(&buf))?;
	defer io::close(input)!;
	let rbuf: [os::BUFSIZ]u8 = [0...];
	const input = &bufio::buffered(input, rbuf, []);

	const keydata = match (bufio::scanline(input)) {
	case let buf: []u8 =>
		yield strings::fromutf8(buf)!;
	case io::EOF =>
		return badstore;
	};
	defer free(keydata);
	const items = strings::split(keydata, ":");
	defer free(items);
	if (len(items) != 5 && len(items) != 7) {
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

	let kv = if (len(items) == 5) {
		yield keyversion::V0;
	} else {
		yield match (strconv::stou8(items[5])) {
		case let v: u8 =>
			if (v > keyversion::V1) {
				return badstore;
			};
			yield v: keyversion;
		case =>
			return badstore;
		};
	};

	let key: [32 + 16]u8 = [0...];
	defer bytes::zero(key);

	const config = argon2::conf {
		mem = mem,
		parallel = 1,
		passes = passes + 3,
		version = argon2::VERSION,
		...
	};
	switch (items[0]) {
	case "argon2i" =>
		if (kv == keyversion::V0) {
			argon2bug::argon2i(key, passphrase, salt, &config)!;
		} else {
			argon2::argon2i(key, passphrase, salt, &config)!;
		};
	case "argon2id" =>
		argon2::argon2id(key, passphrase, salt, &config)!;
	case =>
		return badstore;
	};

	if (!crypto::compare(key[32..], verify)) {
		return badpass;
	};

	store.key = switch (kv) {
	case keyversion::V0 =>
		yield loadv0key(key[..32]);
	case keyversion::V1 =>
		yield loadv1key(key[..32], items[6])?;
	case =>
		abort();
	};

	store.state = state::UNLOCKED;
	match (load_index(store)) {
	case void => yield;
	case let err: io::error =>
		return err;
	case errors::invalid =>
		return badstore;
	};
};

fn loadv0key(key: []u8) keystore::key =
	keystore::newkey(key[..32], "secstore")!;

fn loadv1key(key: []u8, enckey: str) (keystore::key | error) = {
	const buf = bufio::fixed(strings::toutf8(enckey), io::mode::READ);
	const dec = base64::newdecoder(&base64::std_encoding, &buf);
	let masterkey = match (secunbox(&dec, key)) {
	case let b: []u8 =>
		yield b;
	case =>
		return badstore;
	};
	defer {
		bytes::zero(masterkey);
		free(masterkey);
	};

	return keystore::newkey(masterkey, "secstore")!;
};

// Locks the key store, unloading the decryption keys.
export fn lock(store: *secstore) void = {
	match (store.key) {
	case let key: keystore::key =>
		keystore::destroy(key);
		store.key = void;
	case void =>
		yield;
	};
	store.state = state::SOFT_LOCKED;
};

// Closes the secstore, freeing any associated resources.
export fn close(store: *secstore) void = {
	lock(store);
	free_keys(store);
	io::close(store.index)!;
	free(store.dir);
};

fn free_keys(store: *secstore) void = {
	for (let i = 0z; i < len(store.entries); i += 1) {
		entry_finish(&store.entries[i]);
	};
};

// Adds an item to the keystore. The provided query must not have any missing
// values.
export fn add(store: *secstore, q: *query::query) (*entry | locked) = {
	if (store.state != state::UNLOCKED) {
		return locked;
	};

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
	assert(store.key is keystore::key);

	const id = uuid::generate();
	const idstr = uuid::encodestr(id);

	let buf = path::init()!;
	path::set(&buf, store.dir, idstr)!;

	const file = os::create(path::string(&buf), 0o600)!;
	defer io::close(file)!;

	let plain = strings::toutf8(strings::dup(val));
	defer {
		bytes::zero(plain);
		free(plain);
	};
	secbox(file, store.key as keystore::key, plain)!;
	return id;
};

// Encrypts and writes an entry to the index.
fn add_index(store: *secstore, entry: *entry) void = {
	assert(store.key is keystore::key);

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

	const enc = base64::newencoder(&base64::std_encoding, store.index);
	secbox(&enc, store.key as keystore::key, buf)!;
	io::close(&enc)!;
	fmt::fprintln(store.index)!;
};

// Decrypts and loads keystore entries from the index.
fn load_index(store: *secstore) (void | io::error | errors::invalid) = {
	assert(store.key is keystore::key);

	let key: [32]u8 = [0...];
	defer bytes::zero(key);
	keystore::read(store.key as keystore::key, key);

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

		const plaintext = secunbox(&dec, key)?;

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
