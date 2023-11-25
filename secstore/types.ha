use crypto::keystore;
use errors;
use fs;
use io;
use uuid;

export type state = enum {
	// The store is fully unlocked
	UNLOCKED,

	// Partially locked - only secret values are encrypted
	SOFT_LOCKED,

	// Fully locked - all key/value entries are encrypted
	HARD_LOCKED,
};

export type secstore = struct {
	key: (keystore::key | void),
	state: state,
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

fn entry_finish(ent: *entry) void = {
	for (let i = 0z; i < len(ent.pairs); i += 1) {
		const pair = &ent.pairs[i];
		free(pair.key);
		match (pair.value) {
		case let val: str =>
			free(val);
		case uuid::uuid =>
			yield;
		};
	};
};

export type badpass = !void;

export type badstore = !void;

export type locked = !void;

export type dupentry = !void;

export type error = !(fs::error | io::error | badstore
	| badpass | locked | dupentry);

export fn strerror(err: error) const str = {
	match (err) {
	case badstore =>
		return "Found corrupt data in the key store";
	case badpass =>
		return "Incorrect passphrase";
	case locked =>
		return "The keystore is locked";
	case dupentry =>
		return "The keystore does not allow duplicate entries";
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: io::error =>
		return io::strerror(err);
	};
};
