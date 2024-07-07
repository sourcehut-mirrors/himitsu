use fmt;
use strings;
use strconv;

// u32 representation of the version which is `major << 16 | minor << 8 | patch`
export type version = enum u32 {
	INIT = 0 << 16 | 0 << 8 | 0,
	REMEMBER = 0 << 16 | 0 << 8 | 1,
};

fn parse_version(version: str) (u32 | protoerror) = {
	let tokens = strings::split(version, " ");
	defer free(tokens);
	if (len(tokens) != 2 || tokens[0] != "version") {
		return protoerror;
	};

	let nums = strings::split(tokens[1], ".");
	defer free(nums);

	match (version_to_u32(nums)) {
	case let v: u32 =>
		return v;
	case strconv::error =>
		return protoerror;
	};
};

fn version_to_u32(v: []str) (u32 | strconv::error | protoerror) = {
	if (len(v) != 3) return protoerror;

	return strconv::stou8(v[0])?: u32 << 16
		| strconv::stou8(v[1])?: u32 << 8
		| strconv::stou8(v[2])?;
};
