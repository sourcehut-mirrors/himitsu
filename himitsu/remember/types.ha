use errors;
use fmt;
use io;
use memio;
use strconv;
use strings;

// Remembers consent until daemon stops
export type session = void;

// Skips remembering consent, but will ask the next time
export type skip = void;

// Refuse to remember consent and don't ask again
export type refuse = void;

// Remember consent for given timeout in seconds.
export type timeout = i64;

// An option for rembering consent
export type option = (session | timeout | skip | refuse);

// String representation of a remember option
export fn stroption(o: option) str = {
	static let buf: [32] u8 = [0...];
	match (o) {
	case session =>
		return "session";
	case skip =>
		return "skip";
	case refuse =>
		return "refuse";
	case let t: timeout =>
		return fmt::bsprintf(buf, "timeout {}", t: i64);
	};
};

// Parse remember options passed as command arguments. Expects a comma separated
// list.
//
// The caller must free the result after use.
export fn parse_options(options: str) ([]option | errors::invalid | nomem) = {
	let result: []option = [];
	let ok = false;
	defer if (!ok) free(result);
	let tok = strings::tokenize(options, ",");
	for (let o => strings::next_token(&tok)) {
		switch (o) {
		case "session" =>
			append(result, session)?;
		case "skip" =>
			append(result, skip)?;
		case "refuse" =>
			append(result, refuse)?;
		case =>
			match (strconv::stou32(o)) {
			case let t: u32 =>
				append(result, t: timeout)?;
			case strconv::error =>
				free(result);
				return errors::invalid;
			};
		};
	};
	ok = true;
	return result;
};

// Create a comma separated list of options. Caller must free the returend
// value.
export fn optionsstr(options: []option) (str | nomem) = {
	let buf = memio::dynamic();
	defer io::close(&buf)!;
	let first = true;
	for (let o .. options) {
		if (first) {
			first = false;
		} else {
			fmt::fprint(&buf, ",")!;
		};

		match (o) {
		case session =>
			fmt::fprint(&buf, "session")!;
		case refuse =>
			fmt::fprint(&buf, "refuse")!;
		case skip =>
			fmt::fprint(&buf, "skip")!;
		case let t: timeout =>
			fmt::fprintf(&buf, "{}", t)!;
		};
	};
	return strings::dup(memio::string(&buf)!);
};
