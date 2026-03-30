SHELL := /bin/bash

APP := envsync
MIX ?= mix
BINDIR ?= /usr/local/bin
DIST_DIR ?= dist
VERSION ?= $(shell sed -n 's/.*version:[[:space:]]*"\([^"]*\)".*/\1/p' mix.exs | head -n1)
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m)
ARTIFACT := $(DIST_DIR)/$(APP)-$(VERSION)-$(OS)-$(ARCH)

.PHONY: help deps build rebuild test format format-check clean install install-built uninstall dist run

help:
	@echo "EnvSync CLI Make targets"
	@echo ""
	@echo "  make deps          Install Elixir dependencies"
	@echo "  make build         Build escript binary (./envsync)"
	@echo "  make rebuild       Clean + build"
	@echo "  make test          Run test suite"
	@echo "  make format        Format source code"
	@echo "  make format-check  Check formatting"
	@echo "  make install       Install prebuilt binary to $(BINDIR)"
	@echo "  make install-built Build then install (do NOT run with sudo)"
	@echo "  make uninstall     Remove installed binary from $(BINDIR)"
	@echo "  make dist          Build distributable binary in ./dist"
	@echo "  make run           Run local binary help output"
	@echo ""
	@echo "Recommended system install:"
	@echo "  make build && sudo make install"

deps:
	$(MIX) deps.get

build: deps
	$(MIX) escript.build

rebuild: clean build

test:
	$(MIX) test --no-start

format:
	$(MIX) format

format-check:
	$(MIX) format --check-formatted

clean:
	rm -f ./$(APP)
	rm -rf $(DIST_DIR)

install:
	@if [ ! -x ./$(APP) ]; then \
		echo "Binary ./$(APP) not found."; \
		echo "Run 'make build' as your normal user first, then retry install."; \
		exit 1; \
	fi
	install -m 0755 ./$(APP) $(BINDIR)/$(APP)

install-built: build install

uninstall:
	rm -f $(BINDIR)/$(APP)

dist: build
	mkdir -p $(DIST_DIR)
	cp ./$(APP) $(ARTIFACT)
	sha256sum $(ARTIFACT) > $(ARTIFACT).sha256
	@echo "Created:"
	@echo "  $(ARTIFACT)"
	@echo "  $(ARTIFACT).sha256"

run: build
	./$(APP) help
