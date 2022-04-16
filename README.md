# Himitsu

「パスワードは何？」「ひみつですよ！」

Himitsu is a secret storage system for Unix systems. It is suitable for storing
passwords, private keys, and so on.

WIP

## Installation

```
$ make
# make install
```

You also need a prompter. Try one of these:

- [hiprompt-gtk](https://git.sr.ht/~sircmpwn/hiprompt-gtk)

## Usage

Begin by initializing a keystore:

```
$ himitsu-init
```

Then fire up the daemon:

```
$ himitsud
Please enter your passphrase to unlock the keystore: 
```

Then use hiq(1) to interact with it.
