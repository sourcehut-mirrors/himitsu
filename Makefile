.POSIX:
.SUFFIXES:

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

.PHONY: all himitsud himitsu-init hiq check clean
