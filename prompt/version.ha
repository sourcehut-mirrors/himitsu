use fmt;
use strings;
use strconv;

// u32 representation of the version which is `major << 16 | minor << 8 | patch`
export type version = enum u32 {
	INIT = 0 << 16 | 0 << 8 | 0,
	REMEMBER = 0 << 16 | 0 << 8 | 1,
};

fn parse_version(version: str) (u32 | protoerror) = {
	let (cmd, version) = strings::cut(version, " ");
	if (cmd != "version") {
		return protoerror;
	};

	let it = strings::tokenize(version, ".");
	let n: size = 0;
	let result: u32 = 0;
	for (let v => strings::next_token(&it)) {
		if (n > 3) {
			return protoerror;
		};

		match (strconv::stou8(v)) {
		case let part: u8 =>
			result |= (part: u32 << (16 - (n*8)): u8);
		case =>
			return protoerror;
		};

		n += 1;
	};

	if (n != 3) {
		return protoerror;
	};

	return result;
};

@test fn parse_version() void = {
	assert(parse_version("version 1.2.3")! == 66051u32);
	assert(parse_version("") is protoerror);
	assert(parse_version("version") is protoerror);
	assert(parse_version("version 1 2") is protoerror);
	assert(parse_version("verson 1.2.3") is protoerror);
	assert(parse_version("version 1.2.3.4") is protoerror);
	assert(parse_version("version 1.2.344") is protoerror);
};
