use dirs;
use errors;
use fmt;
use io;
use net::unix;
use net;
use os;
use path;
use unix::poll;
use unix::poll::{event};
use unix::signal;

type server = struct {
	sock: *net::listener,
	signalfd: io::file,
	pollfd: []poll::pollfd,
	clients: []client,
};

type client = struct {
	sock: io::file,
	buf: [os::BUFSIZ]u8,
};

export fn bind(signalfd: io::file) server = {
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

export fn shutdown(serv: *server) void = {
	net::shutdown(serv.sock);

	let buf = path::init();
	path::set(&buf, dirs::state("himitsu"), "socket")!;
	os::remove(path::string(&buf))!;

	free(serv.pollfd);
	free(serv.clients); // TODO: Free/close client state
};

export fn dispatch(serv: *server) bool = {
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
			// TODO: Handle EAGAIN
			if (serv.pollfd[i].revents & event::POLLIN != 0) {
				abort(); // TODO
			};
		};
	case errors::interrupted =>
		yield;
	case let err: errors::error =>
		fmt::fatal("poll: {}", errors::strerror(err));
	};
	return true;
};

export fn accept(serv: *server) void = {
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
