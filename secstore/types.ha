use crypto::keystore;
use errors;
use fs;
use io;
use uuid;

export type secstore = struct {
	key: keystore::key,
	dir: str,
	index: io::handle,
	// TODO: Consider adding hash table or btree or something. Might be fun
	// to write the first b-tree in hare and see how it goes
	entries: []entry,
};

export type entry = struct {
	pairs: []pair,
};

export type pair = struct {
	key: str,
	value: (str | uuid::uuid),
};

export type badpass = !void;

export type badstore = !void;

export type error = !(fs::error | io::error | badstore | badpass);

export fn strerror(err: error) const str = {
	match (err) {
	case badstore =>
		return "Found corrupt data in the key store";
	case badpass =>
		return "Incorrect passphrase";
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: io::error =>
		return io::strerror(err);
	};
};
