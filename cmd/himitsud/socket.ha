use bytes;
use dirs;
use encoding::utf8;
use errors;
use fmt;
use io;
use net::unix;
use net;
use os;
use path;
use strings;
use unix::poll;
use unix::poll::{event};
use unix::signal;

def CLIENT_MAXBUF: size = 16777216; // 16 MiB
def MAX_CLIENTS: size = 256;

type server = struct {
	sock: *net::listener,
	signalfd: io::file,
	pollfd: []poll::pollfd,
	clients: []client,
	disconnected: bool,
};

type client_state = enum {
	READ,
	WRITE,
	WRITE_ERROR,
};

type client = struct {
	sock: io::file,
	state: client_state,
	pollfd: *poll::pollfd,
	rbuf: []u8,
	wbuf: []u8,
};

fn bind(signalfd: io::file) server = {
	const statedir = dirs::state("himitsu");
	os::mkdirs(statedir)!;

	let buf = path::init();
	path::set(&buf, statedir, "socket")!;
	const sockpath = path::string(&buf);
	const sock = match (unix::listen(sockpath)) {
	case let l: *net::listener =>
		yield l;
	case let err: net::error =>
		fmt::fatal(net::strerror(err));
	};
	os::chmod(sockpath, 0o700)!;

	let pollfd = alloc([poll::pollfd {
		fd = net::listenerfd(sock) as io::file,
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
		...
	};
};

fn shutdown(serv: *server) void = {
	for (let i = 0z; i < len(serv.clients); i += 1) {
		io::close(serv.clients[i].sock);
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
		for (let i = 2z; i < len(serv.pollfd); i += 1) {
			dispatch_client(serv, &serv.clients[i - 2]);
			if (serv.disconnected) {
				// Restart loop on client disconnect
				serv.disconnected = false;
				i = 2;
			};
		};
	case errors::interrupted =>
		yield;
	case let err: errors::error =>
		fmt::fatal("poll: {}", errors::strerror(err));
	};
	return true;
};

fn accept(serv: *server) void = {
	// TODO: O_NONBLOCK
	const sock = match (net::accept(serv.sock)) {
	case let sock: io::file =>
		yield sock;
	case let err: net::error =>
		fmt::fatal(net::strerror(err));
	};
	if (len(serv.clients) >= MAX_CLIENTS) {
		fmt::println("Max clients exceeded; dropping client")!;
		io::close(sock);
		return;
	};

	append(serv.pollfd, poll::pollfd {
		fd = sock,
		events = event::POLLIN | event::POLLHUP,
		...
	});
	let pollfd = &serv.pollfd[len(serv.pollfd) - 1];
	append(serv.clients, client {
		sock = sock,
		pollfd = pollfd,
		...
	});
};

fn dispatch_client(serv: *server, client: *client) void = {
	const pollfd = client.pollfd;
	if (pollfd.revents & event::POLLERR != 0) {
		disconnect(serv, client);
		return;
	};
	if (pollfd.revents & event::POLLHUP != 0) {
		disconnect(serv, client);
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
		disconnect(serv, client);
		return;
	};
	append(client.rbuf, buf[..z]...);
	if (len(client.rbuf) >= CLIENT_MAXBUF) {
		disconnect_error(client, "error proto buffer exceeded\n");
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
			disconnect_error(client, "error proto invalid UTF-8\n");
			return;
		};
		defer delete(client.rbuf[..i+1]);

		fmt::println(line)!;
		if (line == "error") {
			disconnect_error(client, "test error\n");
			return;
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
		disconnect(serv, client);
		return;
	};
	delete(client.wbuf[..z]);
	if (len(client.wbuf) != 0) {
		return;
	};

	switch (client.state) {
	case client_state::WRITE =>
		client.state = client_state::READ;
	case client_state::WRITE_ERROR =>
		disconnect(serv, client);
	case => abort();
	};
};

fn disconnect(serv: *server, client: *client) void = {
	io::close(client.sock);
	free(client.rbuf);
	free(client.wbuf);

	// XXX: There is no need for this to be O(n) except laziness
	let i = 0z;
	for (i < len(serv.clients); i += 1) {
		if (&serv.clients[i] == client) {
			delete(serv.clients[i]);
			break;
		};
	};
	delete(serv.pollfd[i + 2]);

	serv.disconnected = true;
};

fn disconnect_error(
	client: *client,
	fmt: str,
	args: fmt::field...
) void = {
	free(client.wbuf);
	const msg = fmt::asprintf(fmt, args...);
	client.wbuf = strings::toutf8(msg);
	client.state = client_state::WRITE_ERROR;
	client.pollfd.events = event::POLLOUT | event::POLLHUP;
};
