use sys;

fn harden() void = {
	// Prevent core dumps from being made and debuggers from attaching
	sys::prctl(sys::PR_SET_DUMPABLE, 0, 0, 0, 0)!;
};
