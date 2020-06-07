default: build

build:
	hugo -D
.PHONY: build

up:
	hugo server -D
.PHONY: up
