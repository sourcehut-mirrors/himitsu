himitsu-store(1)

# NAME

himitsu-store - manages the *himitsu*(7) key store

# SYNOPSIS

*himitsu-store [-ir]*

# DESCRIPTION

*himitsu-store* manages the *himitsu*(7) key store at $XDG_DATA_HOME/himitsu.

## OPTIONS

*-i*
	Creates a new *himitsu*(7) key store at $XDG_DATA_HOME/himitsu
	and a new *himitsu.ini*(5) configuration file at
	$XDG_CONFIG_HOME/himitsu/himitsu.ini

*-r*
	Re-encrypts the current store with a newly generated master key.

# SEE ALSO

*himitsu*(7), *himitsud*(1)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
