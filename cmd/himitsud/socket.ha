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

type server = struct {
	sock: *net::listener,
	signalfd: io::file,
	pollfd: []poll::pollfd,
	clients: []client,
};

type client_mode = enum {
	READ,
	WRITE,
};

type client = struct {
	sock: io::file,
	mode: client_mode,
	buf: []u8,
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
	net::shutdown(serv.sock);

	let buf = path::init();
	path::set(&buf, dirs::state("himitsu"), "socket")!;
	os::remove(path::string(&buf))!;

	free(serv.pollfd);
	free(serv.clients); // TODO: Free/close client state
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
			if (serv.pollfd[i].revents & event::POLLERR != 0) {
				abort(); // TODO
			};
			if (serv.pollfd[i].revents & event::POLLHUP != 0) {
				abort(); // TODO
			};
			if (serv.pollfd[i].revents & event::POLLIN != 0) {
				client_readable(serv, &serv.clients[i - 2]);
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

	append(serv.clients, client {
		sock = sock,
		...
	});
	append(serv.pollfd, poll::pollfd {
		fd = sock,
		events = event::POLLIN | event::POLLERR | event::POLLHUP,
		...
	});
};

fn client_readable(serv: *server, client: *client) void = {
	let buf: [os::BUFSIZ]u8 = [0...];
	const z = match (io::read(client.sock, buf)) {
	case let z: size =>
		yield z;
	case let err: io::error =>
		abort(); // TODO: Disconnect client
	};
	append(client.buf, buf[..z]...);
	if (len(client.buf) >= CLIENT_MAXBUF) {
		abort(); // TODO: Disconnect client
	};

	for (true) {
		let i = match (bytes::index(client.buf, '\n')) {
		case let i: size =>
			yield i;
		case void =>
			return;
		};

		const line = match (strings::try_fromutf8(client.buf[..i])) {
		case let s: str =>
			yield s;
		case utf8::invalid =>
			abort(); // TODO: Disconnect client
		};

		fmt::println(line)!;

		delete(client.buf[..i+1]);
	};
};
