use himitsu::query;
use uuid;

export type iterator = struct {
	query: *query::query,
	index: size,
};

// Performs a query against the secstore, returning an iterator that can be
// passed to [[next]] to retrieve matching entries. The query is borrowed for
// the lifetime of the iterator.
// 
// The iterator is not valid if the store is mutated during the iteration.
export fn query(store: *secstore, query: *query::query) iterator = {
	return iterator {
		query = query,
		...
	};
};

// Returns the next matching item from an iterator, or void if none remain.
export fn next(store: *secstore, iter: *iterator) (*entry | void) = {
	for (iter.index < len(store.entries); iter.index += 1) {
		const ent = &store.entries[iter.index];
		if (entry_match(ent, iter.query)) {
			iter.index += 1;
			return ent;
		};
	};
};

fn entry_match(ent: *entry, query: *query::query) bool = {
	for (let i = 0z; i < len(query.items); i += 1) {
		const q = &query.items[i];
		const p = match (findpair(ent, q.key)) {
		case void =>
			if (!q.optional) {
				return false;
			};
			continue;
		case let p: *pair =>
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
	return true;
};

fn findpair(ent: *entry, key: str) (*pair | void) = {
	for (let i = 0z; i < len(ent.pairs); i += 1) {
		if (ent.pairs[i].key == key) {
			return &ent.pairs[i];
		};
	};
};
