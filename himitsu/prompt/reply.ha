use himitsu::remember;
use fmt;
use io;

fn reply_version(p: *prompter, ver: (uint, uint, uint)) (void | io::error) = {
	const (major, minor, patch) = ver;
	fmt::fprintfln(p.out, "version {}.{}.{}", major, minor, patch)?;
};

// Sends a password in response to an [[unlock]] command.
export fn reply_password(p: *prompter, pass: str) (void | io::error) = {
	fmt::fprintfln(p.out, "password {}", pass)?;
};

// Sends the user's [[remember]] selection.
export fn reply_remember(
	p: *prompter,
	r: remember::option,
) (void | io::error) = {
	match (r) {
	case remember::session =>
		fmt::fprintln(p.out, "remember session")?;
	case remember::skip =>
		fmt::fprintln(p.out, "remember skip")?;
	case remember::refuse =>
		fmt::fprintln(p.out, "remember refuse")?;
	case let to: remember::timeout =>
		fmt::fprintfln(p.out, "remember timeout {}", to: i64)?;
	};
};
