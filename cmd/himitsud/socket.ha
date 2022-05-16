use bytes;
use dirs;
use encoding::utf8;
use errors;
use fmt;
use io;
use log;
use net::unix;
use net;
use os;
use path;
use secstore;
use strings;
use unix::poll;
use unix::poll::{event};
use unix::signal;

def CLIENT_MAXBUF: size = 16777216; // 16 MiB
def MAX_CLIENTS: size = 256;
def POLLFD_RESERVED: size = 2;

type server = struct {
	sock: io::file,
	signalfd: io::file,
	pollfd: []poll::pollfd,
	clients: []client,
	disconnected: bool,
	store: *secstore::secstore,
};

fn bind(store: *secstore::secstore, signalfd: io::file) server = {
	const statedir = dirs::state("himitsu");
	os::mkdirs(statedir, 0o755)!;

	let buf = path::init();
	path::set(&buf, statedir, "socket")!;
	const sockpath = path::string(&buf);
	const sock = match (unix::listen(sockpath)) {
	case let l: io::file =>
		yield l;
	case let err: net::error =>
		log::fatal(net::strerror(err));
	};
	os::chmod(sockpath, 0o700)!;

	let pollfd = alloc([poll::pollfd {
		fd = sock,
		events = event::POLLIN,
		...
	}, poll::pollfd {
		fd = signalfd,
		events = event::POLLIN,
		...
	}]);

	return server {
		sock = sock,
		signalfd = signalfd,
		pollfd = pollfd,
		store = store,
		...
	};
};

fn shutdown(serv: *server) void = {
	for (let i = 0z; i < len(serv.clients); i += 1) {
		io::close(serv.clients[i].sock)!;
		free(serv.clients[i].rbuf);
		free(serv.clients[i].wbuf);
	};
	free(serv.clients);
	free(serv.pollfd);

	let buf = path::init();
	path::set(&buf, dirs::state("himitsu"), "socket")!;
	os::remove(path::string(&buf))!;

	net::shutdown(serv.sock);
};

fn dispatch(serv: *server) bool = {
	match (poll::poll(serv.pollfd, poll::INDEF)) {
	case uint =>
		if (serv.pollfd[0].revents & event::POLLIN != 0) {
			accept(serv);
		};
		if (serv.pollfd[1].revents & event::POLLIN != 0) {
			signal::read(serv.signalfd)!;
			return false;
		};
		for (let i = POLLFD_RESERVED; i < len(serv.pollfd); i += 1) {
			dispatch_client(serv, &serv.clients[i - POLLFD_RESERVED]);
			if (serv.disconnected) {
				// Restart loop on client disconnect
				serv.disconnected = false;
				i = POLLFD_RESERVED;
			};
		};
	case errors::interrupted =>
		yield;
	case let err: errors::error =>
		log::fatal("poll:", errors::strerror(err));
	};
	return true;
};

fn accept(serv: *server) void = {
	// TODO: O_NONBLOCK
	const sock = match (net::accept(serv.sock)) {
	case let sock: io::file =>
		yield sock;
	case let err: net::error =>
		log::fatal(net::strerror(err));
	};
	if (len(serv.clients) >= MAX_CLIENTS) {
		log::println("Max clients exceeded; dropping client");
		io::close(sock)!;
		return;
	};

	append(serv.pollfd, poll::pollfd {
		fd = sock,
		events = event::POLLIN | event::POLLHUP,
		...
	});
	const pollfd = &serv.pollfd[len(serv.pollfd) - 1];
	append(serv.clients, client {
		server = serv,
		sock = sock,
		pollfd = pollfd,
		...
	});
};

fn dispatch_client(serv: *server, client: *client) void = {
	const pollfd = client.pollfd;
	if (pollfd.revents & event::POLLERR != 0) {
		disconnect(client);
		return;
	};
	if (pollfd.revents & event::POLLHUP != 0) {
		disconnect(client);
		return;
	};
	if (pollfd.revents & event::POLLIN != 0) {
		client_readable(serv, client);
	};
	if (pollfd.revents & event::POLLOUT != 0) {
		client_writable(serv, client);
	};
};

fn client_readable(serv: *server, client: *client) void = {
	let buf: [os::BUFSIZ]u8 = [0...];
	const z = match (io::read(client.sock, buf)) {
	case let z: size =>
		yield z;
	case let err: io::error =>
		disconnect(client);
		return;
	};
	append(client.rbuf, buf[..z]...);
	if (len(client.rbuf) >= CLIENT_MAXBUF) {
		disconnect_error(client, "error Buffer exceeded\n");
		return;
	};

	for (true) {
		let i = match (bytes::index(client.rbuf, '\n')) {
		case let i: size =>
			yield i;
		case void =>
			return;
		};

		const line = match (strings::try_fromutf8(client.rbuf[..i])) {
		case let s: str =>
			yield s;
		case utf8::invalid =>
			disconnect_error(client, "error Invalid UTF-8\n");
			return;
		};
		defer delete(client.rbuf[..i+1]);
		match (exec(serv, client, line)) {
		case let err: servererror =>
			log::printfln("Error processing user command: {}",
				strerror(err));
		case void =>
			yield;
		};
		if (serv.disconnected) {
			break;
		};
	};
};

fn client_writable(serv: *server, client: *client) void = {
	const z = match (io::write(client.sock, client.wbuf)) {
	case let z: size =>
		yield z;
	case errors::again =>
		return;
	case let err: io::error =>
		disconnect(client);
		return;
	};
	delete(client.wbuf[..z]);
	if (len(client.wbuf) != 0) {
		return;
	};

	switch (client.state) {
	case state::WRITE =>
		client.state = state::READ;
		client.pollfd.events = event::POLLIN | event::POLLHUP;
	case state::WRITE_ERROR =>
		disconnect(client);
	case => abort();
	};
};
