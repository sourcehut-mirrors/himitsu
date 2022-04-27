use fmt;
use io;
use strings;
use unix::poll;
use unix::poll::{event};

type state = enum {
	READ,
	WRITE,
	WRITE_ERROR,
};

type client = struct {
	server: *server,
	sock: io::file,
	state: state,
	pollfd: *poll::pollfd,
	rbuf: []u8,
	wbuf: []u8,
};

// Immediately disconnects a client, without sending them an error message.
fn disconnect(c: *client) void = {
	io::close(c.sock)!;
	free(c.rbuf);
	free(c.wbuf);

	let serv = c.server;
	let i = (c: uintptr - serv.clients: *[*]client: uintptr): size / size(client);
	delete(serv.clients[i]);
	delete(serv.pollfd[i + POLLFD_RESERVED]);

	serv.disconnected = true;
};

// Prepares an error message to send to a client. They will be disconnected once
// the error message is sent.
fn disconnect_error(
	client: *client,
	fmt: str,
	args: fmt::field...
) void = {
	free(client.wbuf);
	const msg = fmt::asprintf(fmt, args...);
	client.wbuf = strings::toutf8(msg);
	client.state = state::WRITE_ERROR;
	client.pollfd.events = event::POLLOUT | event::POLLHUP;
};

// Writes data to the client. Takes ownership over the buffer.
fn write(client: *client, buf: []u8) void = {
	assert(client.state != state::WRITE
		&& client.state != state::WRITE_ERROR);
	client.wbuf = buf;
	client.state = state::WRITE;
	client.pollfd.events = event::POLLOUT | event::POLLHUP;
};

// Writes data to the client. Duplicates the buffer.
fn writebuf(client: *client, buf: []u8) void = {
	write(client, alloc(buf...));
};

// Writes a formatted string to the client.
fn writefmt(
	client: *client,
	fmt: str,
	args: fmt::field...
) void = {
	let buf = fmt::asprintf(fmt, args...);
	let buf = strings::toutf8(buf);
	append(buf, '\n');
	write(client, buf);
};
