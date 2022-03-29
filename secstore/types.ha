use crypto::keystore;
use fs;
use io;

export type secstore = struct {
	key: keystore::key,
	dir: str,
};

export type badpass = !void;

export type error = !(fs::error | io::error | badpass);
