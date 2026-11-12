LUA ?= lua5.3
# luacheck installed by `make dev` (tools/setup-dev.sh) is used when present, else the one on PATH.
LUACHECK ?= $(if $(wildcard .luarocks/bin/luacheck),.luarocks/bin/luacheck,luacheck)

.PHONY: check test lint dev clean

check: lint test

test:
	$(LUA) tests/run.lua

lint:
	$(LUACHECK) .

# Install luacheck into .luarocks/, no sudo needed
dev:
	tools/setup-dev.sh

clean:
	rm -rf build
