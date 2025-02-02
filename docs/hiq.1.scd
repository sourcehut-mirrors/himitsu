hiq(1)

# NAME

hiq - query the *himitsu*(7) key store

# SYNOPSIS

*hiq* [-h1adlLQRs] [-F _field_] _query_...

# DESCRIPTION

*hiq* will query the Himitsu key store for keys matching the given _query_. For
details on the query format, consult *himitsu*(7) under *QUERY SYNTAX*. Matching
keys will be printed to the standard output in the format described by
*himitsu*(7) under *KEY FORMAT*.

The user is not required to use redundant shell quoting to escape keys or values
with special characters; the command line arguments are interpreted as if they
have already been quoted properly.

## OPTIONS

*-h*
	Print help text.

*-1*
	Causes *hiq* to exit with a non-zero status code if greater than one key
	matched the given query.

*-a*
	Adds a new key to the key store. The query must be fully specified, such
	that each key has a value and there are no optional keys. If no command
	line arguments are provided, new keys are read from the standard input.
	Using the standard input is recommended when adding keys from an
	interactive shell, to prevent secret values from being stored in your
	shell history.

*-d*
	Request decryption of secret keys.

*-F* _field_
	Select a specific field to print. By default, the full key is printed in
	the format described by *KEY FORMAT* in *himitsu*(7).

*-l*
	Soft locks the keyring by removing the secret key from memory. Keeps
	non-private data of entries in memory.

*-L*
	Hard locks the keyring by removing the secret key and all entries from
	memory.

*-Q*
	Terminate the Himitsu daemon. Only works if *himitsud*(1) was started
	with the -D flag.

*-R*
	Remove all keys from the key store matching the query. The user is
	prompted to consent before this operation is committed.

*-s*
	Enable strict query mode. Entries must not have more keys than specified
	by the query in order to be matched.

# EXAMPLES

To query for all keys matching *proto=web*:

```
$ hiq proto=web
```

To query for a key matching *proto=web* and *host=example.org* with a required
*username* and *password* and an optional *comment*:

```
$ hiq proto=web host=example.org username password! comment?
```

To query for a key and decrypt it, returning the password field alone:

```
$ hiq -dFpassword proto=web host=example.org
```

To add a new key to the store:

```
$ hiq -a
proto=web host=example.org user=jdoe password!=hunter2
```

To delete all keys matching *host=example.org*:

```
$ hiq -R host=example.org
```

# SEE ALSO

*himitsu*(7), *himitsu-ipc*(5)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
