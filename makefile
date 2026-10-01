# Developer entry points. `make help` lists them.
.PHONY: help build test test-unit test-integration lint format app app-install ci \
	build-debug.sh test.sh swift-test.sh format.sh lint.sh

help:
	@echo "make build             debug build (warnings as errors)"
	@echo "make test              unit + integration tests"
	@echo "make test-unit         XCTest, except *IntegrationTest"
	@echo "make test-integration  *IntegrationTest + CLI binary checks"
	@echo "make lint              swiftformat, swiftlint, periphery"
	@echo "make format            swiftformat"
	@echo "make app               build .release/HyprDarwin.app (no install)"
	@echo "make app-install       build and install to /Applications + ~/.local/bin/hypr"
	@echo "make ci                everything the CI test + lint jobs run"

build:
	./build-debug.sh -Xswiftc -warnings-as-errors

test-unit: build
	./script/test-unit.sh

test-integration: build
	./script/test-integration.sh

test: test-unit test-integration

lint:
	./lint.sh

format:
	./format.sh

app:
	./build-app.sh --no-install

app-install:
	./build-app.sh

ci: test lint
	./generate.sh
	./script/check-uncommitted-files.sh

# Upstream targets, kept so vim's :make works as before
build-debug.sh:
	./build-debug.sh

test.sh:
	./test.sh

swift-test.sh:
	./swift-test.sh

format.sh:
	./format.sh

lint.sh:
	./lint.sh
