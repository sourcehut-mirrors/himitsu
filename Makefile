.POSIX:
.SUFFIXES:

all: himitsud himitsu-init

himitsud:
	hare build -o $@ cmd/$@/

himitsu-init:
	hare build -o $@ cmd/$@/

check:
	hare test

clean:
	rm -f himitsud himitsu-init

.PHONY: himitsud himitsu-init check clean
