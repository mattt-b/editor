SRCS := $(wildcard src/*.odin src/**/*.odin src/**/**/*.odin)

.PHONY: clean test bench

editor: $(SRCS)
	odin build src -out=editor

clean:
	rm -f editor editor.log

test:
	cd tests && odin run .

bench:
	cd bench && odin run . -opt=3 -no-bounds-check
