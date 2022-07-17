himitsu-ipc(5)

# NAME

himitsu-ipc - IPC protocol implemented by *himitsud*(1)

# DESCRIPTION

The Himitsu IPC protocol is a line-oriented text protocol using the UTF-8
encoding and LF line endings. It is transmitted over a Unix socket which is
located at $XDG_RUNTIME_DIR/himitsu.

Interactions with this interface are command/reply oriented, with commands
initiated by the client and replies sent by the server. Both commands and
replies have the same semantic structure. Each begins with a command word (an
alphanumeric string) which defines the operation requested. There may or may not
be additional arguments provided. If there are no additional arguments the
command word is immediately followed by LF. Otherwise, following the command
word is a space, then a sequence of arbitrary printable UTF-8 characters until
the line terminator is reached. The structure of the argument string depends on
the command word.

This man page assumes knowledge of the *KEY FORMAT* and *QUERY SYNTAX* described
in *himitsu*(7). Note also that commands which accept flags process them in a
manner compatible with *getopt*(3).

All commands are subject to a significant delay before the reply while the user
is prompted to provide consent or to unlock the keyring.

# COMMANDS

The following commands are recognized by the server:

*add* _key_...
	Adds a new _key_ to the key store. The server will send a *key* reply
	echoing the new key (without secrets), followed by an *end* reply.

*del* _query_...
	Removes keys from the key store which match the provided _query_. The
	user will be prompted to consent to this operation. The server will send
	a *key* reply for each deleted key (without secrets), followed by an
	*end* reply.

*query* [-d] _query_...
	Queries the key store for keys matching the provided _query_. Matching
	keys are returned via a series of *key* replies, terminated with an
	*end* reply to signal the end of the list. If the -d option is provided,
	the private values will be decrypted after requesting user consent.

*quit*
	Requests that the daemon terminate itself. This command is only
	recognized if *himitsud*(1) was started with the -D flag. No reply is
	sent.

# REPLIES

The following replies are sent to the client:

*key* _key_...
	Provides a single key store entry to the user.

*end*
	Signals the end of a list of *key* replies.

*error* _message_...
	Indicates that a requested operation resulted in an error. The _message_
	is both human-friendly and consistent, such that it can be displayed to
	the user or matched against an internal database of semantic error
	strings in the client.

# EXAMPLE SESSION

An example session, with *<=* indicating messages from the server to the client,
and *=>* vice-versa. Any of the commands may be separated from their replies by
several seconds while the user interacts with the prompter.

```
=> query proto=web
<= key proto=web host=a.example.org user=jdoe password!
<= key proto=web host=b.example.org user=jdoe password!
<= key proto=web host=c.example.org user=jdoe password!
<= key proto=web host=d.example.org user=jdoe password!
<= end
=> add proto=web host=e.example.org user=jdoe password!=hunter2
<= key proto=web host=e.example.org user=jdoe password!
<= end
=> query -d proto=web host=e.example.org
=> key proto=web host=e.example.org user=jdoe password!=hunter2
<= end
```

# SEE ALSO

*himitsu*(7)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
