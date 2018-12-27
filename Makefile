SRCS := $(wildcard src/**/*.odin)

.PHONY: clean

editor: $(SRCS)
	odin build src -out=editor

clean:
	rm -f editor editor.log
