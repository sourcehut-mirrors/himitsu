himitsu(7)

# NAME

himitsu - Himitsu key store

# DESCRIPTION

Himitsu is a secret key storage system. Each key is stored as a set of key/value
pairs, any of which may be secret.

## USAGE

To initialize a new Himitsu key store, run *himitsu-store*(1) with the -i
option. This will create a new key store, and a new configuration file (see
*himitsu.ini*(5)). To begin servicing user requests, the Himitsu daemon must be
running: see *himitsud*(1).

The *hiq*(1) command is provided for querying the key store.

## KEY FORMAT

Each entry is formatted as a set of key/value pairs. Each key and value is
separated by *=* (the "equal" symbol), e.g. key=value, and each key/value pair
is separated with spaces. Keys and values are formatted using shell quoting
syntax, such that spaces or other special characters (non-alphanumeric) may
appear in keys or values if they are quoted according to shell quoting rules.
Keys must be unique within an entry.

Each key may be suffixed with a *!* to indicate that the value is secret.

```
proto=web host=example.org username=jdoe password!="hello world"
```

This format is used for inserting new keys and for reading keys out of the key
store. Applications may read any non-secret keys without permission, but user
consent is required to disclose secret keys. If disclosure is not requested, the
value (along with the *=* token) are omitted for secret keys:

```
proto=web host=example.org username=jdoe password!
```

## QUERY SYNTAX

A query language is provided for searching through the key store for entries
with desirable traits. The syntax is identical to the key format itself, but
introduces the "*?*" suffix, indicating an optional key. A key may also be
specified without a value, which requires that the key is present but does not
require that it has a specific value (in this case, *=* is also omitted).

For example, given the following query:

```
proto=web host username password! comment?
```

The key store will return all entries with *proto=web*, a *host* and *username*
key with any value, a secret *password* key, and an optional *comment* key set
to any value.

## KEY CONVENTIONS

Himitsu does not much care about the format of the keys it stores, but tools
which integrate with Himitsu often do care. Various conventions are defined for
the format of keys to integrate properly with third-party software. Generally,
the *proto* key defines the protocol in use for a given key, such as *proto=web*
for web passwords or *proto=ssh* for SSH keys. Third-party software is
encouraged to ship with man pages at *himitsu-$proto*(5) and *himitsu-$proto*(7)
which respectively document the key conventions and usage for that integration.
Consult these man pages for further information about utilizing Himitsu
integrations.

Such man pages are not included in the Himitsu distribution, but are distributed
by third-party software. For instance, to learn about the SSH integration,
install "himitsu-ssh" and consult *himitsu-ssh*(7) for usage details.

# SEE ALSO

*himitsu-store*(1), *himitsud*(1), *hiq*(1), *himitsu.ini*(5), *himitsu-ipc*(5),
*himitsu-prompter*(5)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
