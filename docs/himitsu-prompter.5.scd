himitsu-prompter(5)

# NAME

himitsu-prompter - protocol used for the *himitsu*(7) prompter

# DESCRIPTION

*himitsud*(1) will invoke the user-configured prompter program in order to
interactively obtain information from the user, such as the password to unlock
the keyring, or consent to the use of a secret key. The prompter may use
whatever means is appropriate to the host environment to obtain this
information, such as using a system-specific UI toolkit.

The prompter is executed by *himitsud*(1) and communicates with the daemon over
the _stdin_ and _stdout_ file descriptors. The protocol is a series of
line-oriented commands and replies encoded as UTF-8 text with LF terminators.
Commands are sent from the daemon to the prompter via _stdin_ and the prompter
writes replies to _stdout_.

Both commands and replies have the same semantic structure. Each begins with a
command word (an alphanumeric string) which defines the operation requested.
There may or may not be additional arguments provided. If there are no
additional arguments the command word is immediately followed by LF. Otherwise,
following the command word is a space, then a sequence of arbitrary printable
UTF-8 characters until the line terminator is reached. The structure of the
argument string depends on the command word.

In this document, examples are provided with the convention that *=>* indicates
messages from the daemon to the prompter via _stdin_, and *<=* vice-versa via
_stdout_.

## HANDSHAKE

The first message the daemon sends is the version command, which identifies the
protocol version in use by the daemon and requests the protocol version in use
by the client. The version number follows the word "version" in the reply, and
is a series of three integers separated by dots ('.'), indicating respectively
the major, minor, and patch version of the protocol.

```
=> version
<= version 1.0.0
```

The protocol number uses semantic versioning to determine compatibility between
different versions of the daemon and prompter. The daemon will determine at its
discretion if this protocol version is suitable, and if so, proceed to issue
additional commands; if not, it will close stdin and the prompter should exit
with status code 1.

The current protocol number is 0.0.1.

## EXIT STATUS

The prompter's exit status is semantically meaningful. The exit status is
interpreted by the daemon as follows:

|[ 0
:< The user consented to the operation
|  1
:  The user did not consent to the operation
|  2-126
:  Reserved for future use
|  127
:  An internal error occured with the prompter

## COMMANDS

The following commands are sent from the daemon to the prompter via _stdin_.

*key* _key_...
	Provides a key to the prompter which is related to this transaction, in
	the format described by *KEY FORMAT* in *himitsu*(7).

*query* _query_
	Provides a query to the prompter which is related to this transaction,
	in the format described by *QUERY SYNTAX* in *himitsu*(7). A query
	command preceeds the *prompt persist* command.

*password* correct|incorrect
	Provides feedback in response to the *password* reply sent from the
	prompter to the daemon. Note that following the *password* reply from
	the prompter, there may be a substantial delay while the password is
	verified. The prompter is encouraged to display some kind of indication
	to the user that this process is underway.

*remember* session|timeout <value>|skip|refuse
	Optional commands to notify the prompter of available options for
	remembering user consent. The prompter should preselect the first
	option received and reply with the selected one, after the *prompt*
	command. The user consent is remembered for the client requesting it.

	- *session*: Until the daemon stops.
	- *timeout <value>*: Until value as seconds have passed or until the
	  session ends, if latter happens earlier.
	- *skip*: Do not remember for now, but may be asked next time.
	- *refuse*: Do not remember and do not ask again for current session.
	  In this case, no remember commands will be send during the remaining
	  session for the query or keys in question.

*prompt* disclose|delete|persist
	Sent when the prompter should obtain consent from the user for the
	desired operation, specified by the given parameter. Preceeding this
	command will be one or more *key* commands describing the keys
	implicated in this operation, in the case of *disclose* or *delete*.
	On *persist* a *query* command preceeds.

	- *disclose*: the specified keys will be disclosed to the client,
	  including secret values.
	- *delete*: the specified keys will be removed from the key store
	- *persist*: the user is asked if the specified query should be
	  remembered. If so, future disclosures of secrets that are matched by
	  the query will be allowed without user consent depending on the
	  selected remember option defined at the *remember* command.

	Following this command, the daemon will wait for a answer to
	given remember options and/or close _stdin_ and will wait for
	the prompter to exit with a meaningful status code as described by *EXIT
	STATUS* above.

*unlock*
	The daemon will send this command when the user must unlock the keyring
	before proceeding. The keyring may be in one of three states:

	- hard locked: all key/value pairs are encrypted
	- soft locked: only secret values are encrypted
	- unlocked: the keyring is fully unlocked

	The keyring is hard locked on startup. In this state, the user cannot
	perform any queries before entering their password. If the prompter
	receives an *unlock* command before any *key* or *prompt* commands are
	sent, the keyring is in this state. The prompter should present the
	unlock UI and send *password* commands until the daemon replies with
	*password correct*. Following this, the keyring will enter the unlocked
	state. If no other operations are required, stdin will be closed after
	*password correct* is sent. However, if a query is pending, the daemon
	will continue normally, sending *key* commands and a *prompt* command to
	complete the desired operation.

	The soft locked mode is entered after the user's configured keyring
	timeout expires. The encryption keys are unloaded from RAM, but the
	decrypted key/value pairs are kept. Queries which do not request
	decryption may proceed normally in this state. However, if decryption of
	secret values is requested, the keyring must be unlocked first. In this
	state, the daemon will send one or more *key* commands, followed by the
	*unlock* command, followed by the *prompt* command. The daemon may
	choose to implement a different unlocking UI in this mode, for instance
	to allow the user to both unlock and consent in a single UI action.

	In either situation, if the user declines to unlock the keyring, the
	prompter should exit with status code 1.

*version*
	See *HANDSHAKE* above.

## REPLIES

The following replies are sent from the prompter to the daemon via _stdout_:

*password* _password_...
	The password reply is sent in response to the *unlock* command after
	the user provides a suitable password. The daemon will send a *password*
	command with feedback on the outcome; see the description of the
	*unlock* command for details. The password itself may contain only
	printable UTF-8 characters.

	Note that the password verification process may require several seconds
	to complete. The prompter implementation is encouraged to provide
	feedback to the user to indicate that the operation is underway.

*remember* session|timeout <value>|skip|refuse
	Notifies the server that the user indicated a desire to remember their
	consent for this operation.

*version* _major_._minor_._patch_
	See *HANDSHAKE* above.

# EXAMPLES

Scenario 1: the keyring is hard locked and the daemon wishes to unlock it.

```
=> version
<= version 0.0.0
=> unlock
=> prompt unlock
<= password hunter3
=> password incorrect
<= password hunter2
=> password correct
(daemon closes stdin)
(prompter exits with status code 0)
```

Scenario 2: the keyring is unlocked and a client would like to view the user's
secret keys.

```
=> version
<= version 0.0.0
=> key proto=web host=example.org user=jdoe password!
=> key proto=web host=example.com user=jdoe password!
=> prompt disclose
(daemon closes stdin)
```

Scenario 3: the keyring is hard locked and a client would like to view the
user's secret keys.

```
=> version
<= version 0.0.0
=> unlock
<= password hunter1
=> password incorrect
<= password hunter2
=> password correct
=> key proto=web host=example.org user=jdoe password!
=> key proto=web host=example.com user=jdoe password!
=> prompt disclose
(daemon closes stdin)
(prompter exits with status code 0)
```

Scenario 4: the keyring is unlocked and a client wants to persist a query.

```
=> version
<= version 0.0.1
=> query proto=web
=> remember session
=> remember timeout 300
=> remember refuse
=> prompt persist
<= remember session
(daemon closes stdin)
(prompter exits with status code0)
```

# SEE ALSO

*himitsu*(7)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
