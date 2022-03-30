use fmt;
use secstore;
use strings;

export fn main() void = {
	const pass = strings::toutf8("hello world");
	match (secstore::open(pass)) {
	case let err: secstore::error =>
		fmt::fatal(secstore::strerror(err));
	case => yield;
	};
};
