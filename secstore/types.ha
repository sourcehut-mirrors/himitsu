use crypto::keystore;
use errors;
use fs;
use io;

export type secstore = struct {
	key: keystore::key,
	dir: str,
};

export type badpass = !void;

export type badstore = !void;

export type error = !(fs::error | io::error | badstore | badpass);

export fn strerror(err: error) const str = {
	match (err) {
	case badstore =>
		return "Found corrupt data in the key store";
	case badpass =>
		return "Incorrect keystore passphrase";
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: io::error =>
		return io::strerror(err);
	};
};
