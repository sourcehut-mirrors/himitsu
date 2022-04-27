use bytes;
use crypto;
use crypto::keystore;
use encoding::base64;
use errors;
use fmt;
use fs;
use io;
use os;
use path;
use shlex;
use strio;
use uuid;

// Serializes a secstore entry to the given I/O handle, returning the number of
// bytes written. The entry is written in its plaintext form, with secret keys
// hidden.
export fn write(
	store: *secstore,
	sink: io::handle,
	ent: *entry,
	private: bool,
) (void | fs::error | io::error | errors::invalid) = {
	// TODO: https://todo.sr.ht/~sircmpwn/hare/619
	for (let i = 0z; i < len(ent.pairs); i += 1) {
		const pair = &ent.pairs[i];
		shlex::quote(sink, pair.key)?;
		match (pair.value) {
		case let val: str =>
			fmt::fprint(sink, "=")?;
			shlex::quote(sink, val)?;
		case let u: uuid::uuid =>
			fmt::fprint(sink, "!")?;
			if (private) {
				// XXX: Maybe shlex::quote should come with a
				// stream-oriented interface
				fmt::fprint(sink, "=")?;
				let buf = strio::dynamic();
				defer io::close(&buf)!;
				write_private(store, &buf, u)?;
				shlex::quote(sink, strio::string(&buf))?;
			};
		};
		if (i + 1 < len(ent.pairs)) {
			fmt::fprint(sink, " ")?;
		};
	};
};

fn write_private(
	store: *secstore,
	sink: io::handle,
	id: uuid::uuid,
) (void | fs::error | io::error | errors::invalid) = {
	const idstr = uuid::encodestr(id);

	let buf = path::init();
	path::set(&buf, store.dir, idstr)!;

	const file = os::open(path::string(&buf))?;
	defer io::close(file)!;

	let mac: crypto::mac = [0...];
	let nonce: crypto::nonce = [0...];
	io::readall(file, mac)?;
	io::readall(file, nonce)?;
	let ciphertext = io::drain(file)?;
	defer {
		bytes::zero(ciphertext);
		free(ciphertext);
	};

	let key: [32]u8 = [0...];
	defer bytes::zero(key);
	keystore::read(store.key, key);

	let box: crypto::box = (mac, nonce, ciphertext);
	const plaintext = crypto::decrypt(&key, &box)?;
	io::writeall(sink, plaintext)?;
};
