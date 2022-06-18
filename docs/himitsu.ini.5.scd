himitsu.ini(5)

# NAME

*himitsu.ini* - configuration file for *himitsu*(7)

# FILE FORMAT

The Himitsu configuration file is an INI file. Each set of options is grouped
into sections, which are indicated by the section name surrounded by square
brackets (e.g. [himitsud]) on a line. Following each section, a set of key/value
pairs belonging to that section are provided. The keys are separated from the
values by an equal symbol (*=*).

The default configuration file is installed by *himitsu-init*(1).

# APPLICATION USAGE

The set of configuration parameters recognized by the Himitsu distribution are
specified below. Third-party software providing Himitsu integrations are
encouraged to configure themselves using this file. Any sections or keys which
are not understood by any particular application will be disregarded.

## HIMITSUD

*himitsud*(1)-related options are placed into the [himitsud] section. The
available options are:

*prompter*
	Configure the path to the prompter executable which will be used to
	interact with the user for consent requests and key store unlock
	operations. See *himitsu-prompter*(5) for a description of the protocol
	which should be implemented by this executable.

# SEE ALSO

*himitsu*(7)

# AUTHORS

Maintained by Drew DeVault <sir@cmpwn.com>, who is assisted by other
contributors. Up-to-date source code can be found at
https://git.sr.ht/~sircmpwn/himitsu, and bugs/patches can be submitted by email
to ~sircmpwn/himitsu-devel@lists.sr.ht.
