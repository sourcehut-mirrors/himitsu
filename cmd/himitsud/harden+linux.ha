use rt;

fn harden() void = {
	// Prevent core dumps from being made and debuggers from attaching
	rt::prctl(rt::PR_SET_DUMPABLE, 0, 0, 0, 0)!;
};
