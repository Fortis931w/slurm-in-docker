SLURM_VERSION = 21.08.8-2
IMAGE = slurm.base

DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all build clean test

all: build

build:
	cp -r -f "$(DIR)/../packages/rpms" .
	docker build -t $(IMAGE) .

clean:
	@[ -z $(docker images -q $(IMAGE)) ] || docker rmi $(IMAGE)
	rm -rf rpms