.POSIX:
.SUFFIXES:
HARE=hare
HAREFLAGS=

DESTDIR=
PREFIX=/usr/local
SRCDIR=$(PREFIX)/src
HARESRCDIR=$(SRCDIR)/hare
THIRDPARTYDIR=$(HARESRCDIR)/third-party

all: himitsud himitsu-init hiq

himitsud:
	hare build -o $@ cmd/$@/

himitsu-init:
	hare build -o $@ cmd/$@/

hiq:
	hare build -o $@ cmd/$@/

check:
	hare test

clean:
	rm -f himitsud himitsu-init hiq

install:
	mkdir -p $(DESTDIR)$(THIRDPARTYDIR)/himitsu/client
	mkdir -p $(DESTDIR)$(THIRDPARTYDIR)/himitsu/query
	install -m644 himitsu/client/* $(DESTDIR)$(THIRDPARTYDIR)/himitsu/client
	install -m644 himitsu/query/* $(DESTDIR)$(THIRDPARTYDIR)/himitsu/query

uninstall:
	rm -rf $(DESTDIR)$(THIRDPARTYDIR)/himitsu

.PHONY: all himitsud himitsu-init hiq check clean install uninstall
