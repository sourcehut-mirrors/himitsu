use himitsu::query;
use himitsu::remember;

// A key command, sending a key associated with the prompter transaction.
export type key = query::query;

// A query command, sending a query associated with the prompter transaction.
export type query = query::query;

// An update command, sending a query associated with the prompter transaction.
export type update = query::query;

// A password command, indicating the result of an unlock operation. True if the
// password was correct.
export type password = bool;

// A remember command, indicating that the user can consent to future
// operations similar to this one. The prompter should follow up with
// a [[reply_remember]] indicating the user's choice (if any).
export type remember = remember::option;

// Prompt the user to take an action: disclose one or more [[key]]s, delete one
// or more [[key]]s, answer a request to remember a [[query]], or update
// entries.
export type prompt = enum uint {
	DISCLOSE,
	DELETE,
	PERSIST,
	UPDATE
};

// Attempt to unlock the keyring: prompt the user for a password and send it to
// the prompter via [[reply_password]], then expect a [[password]] command back
// to inform the prompter of the outcome.
export type unlock = void;

// Version command. This command is handled internally.
export type version = void;

// A tagged union of all possible prompter commands.
export type command = (key | query | update | password
	| remember | prompt | unlock | version);

// Frees resources associated with a [[command]].
export fn command_finish(cmd: *command) void = {
	match (cmd) {
	case let key: *key =>
		query::finish(key: *query::query);
	case let q: *query =>
		query::finish(q: *query::query);
	case => void;
	};
};
