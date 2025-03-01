use os;

// Possible exit statuses that the prompter can use with [[exit]].
export type status = enum int {
	CONSENT = 0,
	DO_NOT_CONSENT = 1,
	INTERNAL_ERROR = 127,
};

// Exit with the given [[status]] code.
export fn exit(status: status) never = {
	os::exit(status: int);
};
