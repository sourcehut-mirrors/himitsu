use errors;
use himitsu::query;
use io;

// All possible errors returned by this module.
export type error = !(query::error | io::error | nomem);

// Returns a human-friendly representation of an [[error]].
export fn strerror(err: error) const str = {
	match (err) {
	case let err: query::error =>
		return query::strerror(err);
	case let err: io::error =>
		return io::strerror(err);
	case nomem =>
		return errors::strerror(nomem);
	};
};
