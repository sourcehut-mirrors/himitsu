.POSIX:
.SUFFIXES:
HARE=hare
HAREFLAGS=
SCDOC=scdoc

DESTDIR=
PREFIX=/usr/local
SRCDIR=$(PREFIX)/src
SHAREDIR=$(PREFIX)/share
MANDIR=$(SHAREDIR)/man
HARESRCDIR=$(SRCDIR)/hare
THIRDPARTYDIR=$(HARESRCDIR)/third-party

CMDS=\
	himitsud \
	himitsu-store \
	hiq \
	hiprompt-tty

all: $(CMDS) docs

$(CMDS):
	$(HARE) build $(HAREFLAGS) -o $@ cmd/$@/

check:
	hare test

DOCS=\
     himitsud.1 \
     himitsu-store.1 \
     hiq.1 \
     himitsu.ini.5 \
     himitsu-ipc.5 \
     himitsu-prompter.5 \
     himitsu.7

docs: $(DOCS)

$(DOCS):
	$(SCDOC) <docs/$@.scd >$@

himitsud.1: docs/himitsud.1.scd
himitsu-store.1: docs/himitsu-store.1.scd
hiq.1: docs/hiq.1.scd
himitsu.ini.5: docs/himitsu.ini.5.scd
himitsu-ipc.5: docs/himitsu-ipc.5.scd
himitsu-prompter.5: docs/himitsu-prompter.5.scd
himitsu.7: docs/himitsu.7.scd

clean:
	rm -f himitsud himitsu-store hiq himitsu-tty $(DOCS)

install:
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(THIRDPARTYDIR)/himitsu/client
	mkdir -p $(DESTDIR)$(THIRDPARTYDIR)/himitsu/query
	mkdir -p $(DESTDIR)$(MANDIR)/man1
	mkdir -p $(DESTDIR)$(MANDIR)/man5
	mkdir -p $(DESTDIR)$(MANDIR)/man7
	install -m755 himitsud himitsu-store hiq hiprompt-tty $(DESTDIR)$(PREFIX)/bin
	install -m644 himitsu/client/* $(DESTDIR)$(THIRDPARTYDIR)/himitsu/client
	install -m644 himitsu/query/* $(DESTDIR)$(THIRDPARTYDIR)/himitsu/query
	install -m644 himitsud.1 $(DESTDIR)$(MANDIR)/man1/himitsud.1
	install -m644 himitsu-store.1 $(DESTDIR)$(MANDIR)/man1/himitsu-store.1
	install -m644 hiq.1 $(DESTDIR)$(MANDIR)/man1/hiq.1
	install -m644 himitsu.ini.5 $(DESTDIR)$(MANDIR)/man5/himitsu.ini.5
	install -m644 himitsu-ipc.5 $(DESTDIR)$(MANDIR)/man5/himitsu-ipc.5
	install -m644 himitsu-prompter.5 $(DESTDIR)$(MANDIR)/man5/himitsu-prompter.5
	install -m644 himitsu.7 $(DESTDIR)$(MANDIR)/man7/himitsu.7

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/himitsud \
	      $(DESTDIR)$(PREFIX)/bin/himitsu-store \
	      $(DESTDIR)$(PREFIX)/bin/hiq \
	      $(DESTDIR)$(PREFIX)/bin/himitsu-tty
	rm -rf $(DESTDIR)$(THIRDPARTYDIR)/himitsu

.PHONY: all himitsud himitsu-store hiprompt-tty hiq check clean install uninstall docs
