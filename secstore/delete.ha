use himitsu::query;
use io;
use os;
use path;
use strings;
use uuid;

// Deletes all keys from the secstore which match the given query.
export fn del(store: *secstore, q: *query::query) (void | locked) = {
	// TODO: TOCTU the keystore key to avoid expiry race
	if (store.key is void) {
		return locked;
	};

	// XXX: Should we bubble up errors from here? If we have an open
	// secstore we presumably have access to it but if someone fucks about
	// it could cause problems here.
	for (let i = 0z; i < len(store.entries); i += 1) {
		const ent = &store.entries[i];
		if (entry_match(ent, q, false)) { // TODO
			delkeys(store, &store.entries[i]);
			delete(store.entries[i]);
			i -= 1;
		};
	};

	io::close(store.index)!;

	let buf = path::init()!;
	path::set(&buf, store.dir, "index")!;
	const oldpath = strings::dup(path::string(&buf));
	defer free(oldpath);
	path::push(&buf, "..", "index.1")!;

	const index = os::create(path::string(&buf), 0o600)!;
	for (let entry &.. store.entries) {
		add_index(store, entry);
	};

	store.index = index;
	os::move(path::string(&buf), oldpath)!;
};

fn delkeys(store: *secstore, entry: *entry) void = {
	let buf = path::init()!;

	for (let pair &.. entry.pairs) {
		const id = match (pair.value) {
		case let id: uuid::uuid =>
			yield id;
		case => continue;
		};

		path::set(&buf, store.dir, uuid::encodestr(id))!;
		os::remove(path::string(&buf))!;
	};
};
