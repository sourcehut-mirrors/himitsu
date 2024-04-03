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
use memio;
use uuid;

// Serializes a secstore entry to the given I/O handle, returning the number of
// bytes written. The entry is written in its plaintext form, with secret keys
// hidden.
export fn write(
	store: *secstore,
	sink: io::handle,
	ent: *entry,
	private: bool,
) (size | error) = {
	if (private && store.state != state::UNLOCKED) {
		return locked;
	};

	let z = 0z;
	for (let i = 0z; i < len(ent.pairs); i += 1) {
		const pair = &ent.pairs[i];
		z += shlex::quote(sink, pair.key)?;
		match (pair.value) {
		case let val: str =>
			z += fmt::fprint(sink, "=")?;
			z += shlex::quote(sink, val)?;
		case let u: uuid::uuid =>
			z += fmt::fprint(sink, "!")?;
			if (private) {
				// XXX: Maybe shlex::quote should come with a
				// stream-oriented interface
				z += fmt::fprint(sink, "=")?;
				let buf = memio::dynamic();
				defer io::close(&buf)!;
				write_private(store, &buf, u)?;
				z += shlex::quote(sink, memio::string(&buf)!)?;
			};
		};
		if (i + 1 < len(ent.pairs)) {
			z += fmt::fprint(sink, " ")?;
		};
	};

	return z;
};

fn write_private(
	store: *secstore,
	sink: io::handle,
	id: uuid::uuid,
) (void | error) = {
	assert(store.key is keystore::key);

	const idstr = uuid::encodestr(id);

	let buf = path::init()!;
	path::set(&buf, store.dir, idstr)!;

	const file = os::open(path::string(&buf))?;
	defer io::close(file)!;

	let plaintext = match (secunbox(file, store.key as keystore::key)) {
	case let b: []u8 =>
		yield b;
	case =>
		return badstore;
	};
	defer {
		bytes::zero(plaintext);
		free(plaintext);
	};

	io::writeall(sink, plaintext)?;
};
