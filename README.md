# Himitsu

「パスワードは何？」「ひみつですよ！」

**Notice: neither this project nor the underlying cryptograhic implementation
have been independently audited. This project is a work in progress.**

Himitsu is a secret storage system for Unix systems. It is suitable for storing
passwords, private keys, and so on.

We hang out in #himitsu on Libera Chat. Please send patches to
[the himitsu-devel mailing list](https://lists.sr.ht/~sircmpwn/himitsu-devel)
using the following address: <~sircmpwn/himitsu-devel@lists.sr.ht>.

## Installation

```
$ make
# make install
```

You also need a prompter. Try one of these:

- [hiprompt-gtk-py](https://git.sr.ht/~sircmpwn/hiprompt-gtk-py)

## Usage

Begin by initializing a keystore:

```
$ himitsu-store
```

Then fire up the daemon:

```
$ himitsud
Please enter your passphrase to unlock the keystore: 
```

Then use hiq(1) to interact with it.

## Library usage

The himitsu package provides a "himitsu" Hare module which provides some support
code for integrations such as new prompters and agents. Consult haredoc for
usage details.
