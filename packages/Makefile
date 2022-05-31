SLURM_VERSION = 21.08.8-2
IMAGE = rpmbuilder

DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all build clean test

all: build

build: rpms

rpms:
	docker build -t $(IMAGE) .
	docker run --rm \
			-e SLURM_VERSION=$(SLURM_VERSION) \
			-v "$(DIR)/rpms:/packages" $(IMAGE)

clean:
	@[ -z $(docker images -q $(IMAGE)) ] || docker rmi $(IMAGE)
	rm -rf rpms
