default: run

run:
	hugo server -D --disableFastRender
.PHONY: run

build:
	hugo -D
.PHONY: build
