SRCS := $(wildcard src/*.odin src/**/*.odin src/**/**/*.odin)

.PHONY: clean bench

editor: $(SRCS)
	odin build src -out=editor

clean:
	rm -f editor editor.log

bench:
	cd bench && odin run . -opt=3 -no-bounds-check
