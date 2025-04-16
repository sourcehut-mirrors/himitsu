use bytes;
use crypto::keystore;
use errors;
use fs;
use io;
use strings;
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
	store: *secstore,
	pairs: []pair,
};

export type pair = struct {
	key: str,
	value: (str | uuid::uuid),
};

fn entry_finish(ent: *entry) void = {
	for (let pair &.. ent.pairs) {
		free(pair.key);
		match (pair.value) {
		case let val: str =>
			bytes::zero(strings::toutf8(val));
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

export type nullentry = !void;

export type incomplete = !void;

export type error = !(fs::error | io::error | nomem | badstore
	| badpass | locked | dupentry | nullentry | incomplete);

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
	case nullentry =>
		return "The keystore does not allow empty entries";
	case incomplete =>
		return "All keys must have a value.";
	case nomem =>
		return "Allocation failure";
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: io::error =>
		return io::strerror(err);
	};
};
