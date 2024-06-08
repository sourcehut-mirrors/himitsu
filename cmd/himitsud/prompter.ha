use himitsu::query;
use himitsu::remember;
use prompt;
use secstore;

type prompter = struct {
	serv: *server,
	prompter: (prompt::prompter | void),
};

fn new_prompter(serv: *server) prompter = prompter {
	serv = serv,
	prompter = void,
};

fn prompter_get(p: *prompter) (prompt::prompter | prompt::error) = {
	match (p.prompter) {
	case let p: prompt::prompter =>
		return p;
	case void =>
		let prompter = prompt::newprompter(p.serv.conf.prompter[0],
			p.serv.conf.prompter[1..])?;
		p.prompter = prompter;
		return prompter;
	};
};

fn prompter_version(p: *prompter) (u32 | prompt::error) =
	prompter_get(p)?.version;

fn prompter_unlock(p: *prompter) (bool | prompt::error) = {
	if (p.serv.store.state == secstore::state::UNLOCKED) {
		return true;
	};

	let prompter = prompter_get(p)?;
	prompt::unlock(&prompter)?;
	return prompt::wait_unlock(&prompter, p.serv.store)?;
};

fn prompter_send_keys(p: *prompter, entries: []*secstore::entry) (void | prompt::error) = {
	let prompter = prompter_get(p)?;

	for (let e .. entries) {
		prompt::sendkey(&prompter, p.serv.store, e)?;
	};
};

fn prompter_send_query(p: *prompter, q: *query::query) (void | prompt::error) = {
	let prompter = prompter_get(p)?;
	prompt::send_query(&prompter, q)?;
};

fn prompter_send_remember(
	p: *prompter,
	rememberopts: []remember::option,
) (void | prompt::error) = {
	let prompter = prompter_get(p)?;
	prompt::send_remember(&prompter, rememberopts)?;
};

fn prompter_wait_remember(
	p: *prompter,
) (remember::option | prompt::error) = {
	let prompter = prompter_get(p)?;
	return prompt::wait_remember(&prompter)?;
};

fn prompter_prompt(p: *prompter, mode: prompt::mode) (void | prompt::error) = {
	let prompter = prompter_get(p)?;
	prompt::prompt(&prompter, mode)?;
};

fn prompter_wait(p: *prompter) (bool | prompt::error) = {
	let prompter = prompter_get(p)?;
	p.prompter = void;
	return prompt::wait(&prompter)?;
};

fn prompter_close(p: *prompter) void = {
	match (p.prompter) {
	case prompt::prompter =>
		prompt::close(&(p.prompter: prompt::prompter))!;
	case void => void;
	};
	p.prompter = void;
};
