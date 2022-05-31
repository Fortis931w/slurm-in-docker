subdir = packages base controller worker 

.PHONY: all build clean lint test $(subdir)

all: build

build: $(subdir)

clean: $(subdir)


lint:
	shellcheck **/*.sh

controller worker : base

base: packages

$(subdir):
	$(MAKE) -C $@ $(MAKECMDGOALS)
