use himitsu::query;
use himitsu::remember;
use prompt;
use secstore;
use strconv;
use strings;
use time;

fn filter_unremembered(
	client: *client,
	matches: []*secstore::entry,
	entry_refused: *bool,
) ([]*secstore::entry | nomem) = {
	let unrem: []*secstore::entry = [];
	let ok = false;
	defer if (!ok) free(unrem);

	for (let m .. matches) {
		let r = find_remember(client, m);
		if (r is remember::refuse) {
			*entry_refused = true;
		};

		match (r) {
		case (remember::session | remember::timeout) => void;
		case (remember::skip | remember::refuse) =>
			append(unrem, m)?;
		};
	};
	ok = true;
	return unrem;
};

fn add_remember(
	client: *client,
	query: query::query,
	kind: remember::option,
	strict: bool
) (void | nomem) = {
	if (kind is remember::skip) {
		return;
	};

	let now = time::now(time::clock::MONOTONIC);
	append(client.remembers, remember {
		query = query,
		strict = strict,
		kind = kind,
		timestamp = time::unix(now),
	})?;
};

// Finds remember for given query or secstore entry. A remembered query matches
// given query, if it the remembered one is a sub query. If there are multiple
// query matches the one with the highes precedence is chosen (refuse > session
// > timeout).
//
// If no remember was found, remember::skip is returned.
fn find_remember(
	c: *client,
	q: (*query::query | *secstore::entry)
) remember::option = {
	let option: remember::option = remember::skip;
	for (let i = 0z; i < len(c.remembers); i += 1) {
		let r = &c.remembers[i];

		match (q) {
		case let q: *query::query =>
			if ((r.strict && !query::is_equal(&r.query, q))
					|| (!r.strict && !query::is_sub(&r.query, q))) {
				continue;
			};
		case let e: *secstore::entry =>
			if (!secstore::entry_match(e, &r.query, true)) {
				continue;
			};
		};

		match (r.kind) {
		case let t: remember::timeout =>
			if (option is remember::session) {
				continue;
			};
			let now = time::unix(time::now(time::clock::MONOTONIC));
			assert(now > 0);
			let passed = now - r.timestamp;
			if (passed >= t) {
				delete(c.remembers[i]);
				i -= 1;
				continue;
			};
			option = t - passed;
		case remember::session =>
			option = remember::session;
		case remember::refuse =>
			return remember::refuse;
		case remember::skip =>
			abort("skip must not be stored");
		};

		if (q is *secstore::entry) {
			return option;
		};
	};
	return option;
};

fn is_remembered(c: *client, q: (*query::query | *secstore::entry)) bool = {
	match (find_remember(c, q)) {
	case (remember::timeout | remember::session) =>
		return true;
	case (remember::skip | remember::refuse) =>
		return false;
	};
};
