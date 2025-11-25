use errors;
use fs;
use io;
use os::exec;

// Returned when the prompter process does not confirm to the protocol.
export type protoerror = !void;

// Returned when the prompter process exits with an internal error;
export type prompterror = !void;

// All possible prompter errors.
export type error = !(protoerror | prompterror
	| io::error | fs::error | exec::error);

// Converts an [[error]] to a human-friendly form.
export fn strerror(err: error) const str = {
	match (err) {
	case protoerror =>
		return "Protocol error";
	case prompterror =>
		return "Prompter reported internal error";
	case let err: fs::error =>
		return fs::strerror(err);
	case let err: io::error =>
		return io::strerror(err);
	case let err: exec::error =>
		if (err is exec::nocmd) {
			return "Could not run prompter: command not found";
		};
		return exec::strerror(err);
	};
};
