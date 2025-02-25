himitsud(1)

# NAME

himitsud - *himitsu*(7) key ring daemon

# SYNOPSIS

*himitsud* [-DR]

# DESCRIPTION

The *himitsud* command runs the Himitsu key ring daemon. It creates a socket at
$XDG_RUNTIME_DIR/himitsu which accepts commands using the *himitsu-ipc*(5)
protocol. Users will generally use *hiq*(1) or other clients to interact with
it.

The user must have initialized a key store with *himitsu-store*(1) before running
the daemon.

For a general introduction to Himitsu, see *himitsu*(7).

# OPTIONS

The following options are recognized by *himitsud*:

*-C* <_path_>
	Path to configuration file to use (see *himitsu.ini*(5)).

*-D*
	Daemonize (fork) the himitsud process after startup.

*-R fd*
	Notify readiness by writing *READY=1\n* into *fd* and then closing.

# SEE ALSO

*himitsu*(7), *himitsu-store*(1), *hiq*(1), *himitsu.ini*(5), *himitsu-ipc*(5),
*himitsu-prompter*(5)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
