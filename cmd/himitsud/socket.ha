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

type server = struct {
	sock: *net::listener,
	clients: []client,
	pollfd: []poll::pollfd,
};

type client = struct {
	sock: io::file,
	buf: [os::BUFSIZ]u8,
};

export fn bind() server = {
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
	}]);

	return server {
		sock = sock,
		pollfd = pollfd,
		...
	};
};

export fn shutdown(serv: *server) void = {
	net::shutdown(serv.sock);
	free(serv.pollfd);
	free(serv.clients); // TODO: Free/close client state
};

export fn dispatch(serv: *server) void = {
	match (poll::poll(serv.pollfd, poll::INDEF)) {
	case uint =>
		if (serv.pollfd[0].revents & event::POLLIN != 0) {
			accept(serv);
		};
		for (let i = 1z; i < len(serv.pollfd); i += 1) {
			if (serv.pollfd[i].revents & event::POLLIN != 0) {
				abort(); // TODO
			};
		};
	case let err: errors::error =>
		fmt::fatal(errors::strerror(err));
	};
};

export fn accept(serv: *server) void = {
	abort(); // TODO
};
