use secstore;
use strings;

export fn main() void = {
	const pass = strings::toutf8("hello world");
	secstore::create(pass)!;
};
