use fmt;

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

