SLURM_VERSION = 21.08.8-2
IMAGE = slurm.controller

.PHONY: all build clean test


all: build

build:
	docker build -t $(IMAGE) .

clean:
	@[ -z $(docker images -q $(IMAGE)) ] || docker rmi $(IMAGE)