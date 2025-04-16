use himitsu::query;
use io;
use memio;
use strings;
use uuid;

export type iterator = struct {
	query: *query::query,
	strict: bool,
	index: size,
};

// Performs a query against the secstore, returning an iterator that can be
// passed to [[next]] to retrieve matching entries. The query is borrowed for
// the lifetime of the iterator.
//
// The iterator is not valid if the store is mutated during the iteration.
export fn query(
	store: *secstore,
	query: *query::query,
	strict: bool
) iterator = {
	return iterator {
		query = query,
		strict = strict,
		...
	};
};

// Returns the next matching item from an iterator, or done if none remain.
export fn next(store: *secstore, iter: *iterator) (*entry | done) = {
	for (iter.index < len(store.entries); iter.index += 1) {
		const ent = &store.entries[iter.index];
		if (entry_match(ent, iter.query, iter.strict)) {
			iter.index += 1;
			return ent;
		};
	};
	return done;
};

// Returns whether 'query' matches 'ent'.
export fn entry_match(ent: *entry, query: *query::query, strict: bool) bool = {
	let nmatched = 0z;
	for (let q &.. query.items) {
		const p = match (findpair(ent, q.key)) {
		case void =>
			if (!q.optional) {
				return false;
			};
			continue;
		case let p: *pair =>
			nmatched += 1;
			yield p;
		};
		match (p.value) {
		case let s: str =>
			if (q.value != "" && q.value != s) {
				return false;
			};
		case uuid::uuid =>
			if (!q.private) {
				return false;
			};
		};
	};

	if (strict && nmatched != len(ent.pairs)) {
		return false;
	};

	return true;
};

fn findpair(ent: *entry, key: str) (*pair | void) = {
	for (let pair &.. ent.pairs) {
		if (pair.key == key) {
			return pair;
		};
	};
};

// Converts an entry to it's matching query. The caller must finish the query
// with [[himitsu::query::finish]].
export fn entry_to_query(
	ent: *entry,
	decrypt: bool = false,
) (query::query | nomem) = {
	let q = query::query {
		...
	};
	let ok = false;
	defer if (!ok) query::finish(&q);

	for (let p &.. ent.pairs) {
		append(q.items, query::pair {
			...
		})?;
		let i = &q.items[len(q.items)-1];
		i.key = strings::dup(p.key)?;
		i.optional = false;

		match (p.value) {
		case let v: str =>
			i.value = strings::dup(v)?;
		case let u: uuid::uuid =>
			i.private = true;
			if (decrypt) {
				let buf = memio::dynamic();
				match (write_private(ent.store, &buf, u)) {
				case void =>
					i.value = memio::string(&buf)!;
				case let e: error =>
					io::close(&buf)!;
					return nomem;
				};
			};
		};
	};
	ok = true;
	return q;
};
