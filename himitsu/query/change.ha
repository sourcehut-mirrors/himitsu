use crypto;
use strings;

// Applies 'changes' to query 'q'. Returns a new query that keeps the order of
// keys that remain from 'q'. Newly added keys are appended. The caller must
// pass the return value to [[finish]] when they are done with it.
export fn change(q: *query, changes: *query) (query | nomem) = {
	let ok = false;
	let new: query = query { ... };
	defer if (!ok) finish(&new);

	let updateadd: []bool = alloc([true...], len(changes.items))?;
	defer free(updateadd);

	for :outer (const p .. q.items) {
		for (let i = 0z; i < len(changes.items); i += 1) {
			const cpair = changes.items[i];
			if (cpair.key != p.key) continue;

			updateadd[i] = false;

			if (cpair.value == "") {
				continue :outer;
			};

			const equal = if (!p.private) {
				yield p.value == cpair.value;
			} else {
				yield crypto::compare(strings::toutf8(p.value),
					strings::toutf8(cpair.value));
			};
			if (equal && p.private == cpair.private)  {
				continue;
			};

			let dup = pair { ... };
			let dupok = false;
			defer if (!dupok) finish_pair(&dup);

			dup.key = strings::dup(cpair.key)?;
			dup.value = strings::dup(cpair.value)?;
			dup.private = cpair.private;

			append(new.items, dup)?;
			dupok = true;
			continue :outer;
		};

		let keep = dup_pair(&p)?;
		if (append(new.items, keep) is nomem) {
			finish_pair(&keep);
			return nomem;
		};
	};

	for (let i = 0z; i < len(updateadd); i += 1) {
		if (!updateadd[i]) continue;

		let add = changes.items[i];
		if (add.value == "") continue;

		let add = dup_pair(&changes.items[i])?;
		if (append(new.items, add) is nomem) {
			finish_pair(&add);
			return nomem;
		};
	};

	ok = true;
	return new;
};
