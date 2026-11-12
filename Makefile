LUA ?= lua5.3
# Tools installed by `make dev` (tools/setup-dev.sh) are used when present, else the ones on PATH.
LUACHECK ?= $(if $(wildcard .luarocks/bin/luacheck),.luarocks/bin/luacheck,luacheck)
PYTHON   ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

.PHONY: check test lint screens docs-images dev clean

check: lint test

test:
	$(LUA) tests/run.lua

lint:
	$(LUACHECK) .

# Install luacheck (.luarocks/) and a Python venv with requirements.txt (.venv/), no sudo needed
dev:
	tools/setup-dev.sh

# Render every screen the tests draw into build/screens/*.png
screens:
	rm -rf build/screens && mkdir -p build/screens
	SCREENS=build/screens $(LUA) tests/run.lua
	$(PYTHON) tools/render_screens.py build/screens build/screens
	$(PYTHON) tools/render_hud.py build/screens build/screens

# Refresh the images used in the docs
docs-images: screens
	mkdir -p docs/images
	cp build/screens/dashboard-alert.png docs/images/dashboard.png
	cp build/screens/dashboard-tier2.png docs/images/dashboard-tier2.png
	cp build/screens/hud-quiet.png docs/images/hud-quiet.png
	cp build/screens/hud-alerts.png docs/images/hud-alerts.png
	cp build/screens/hud-editor.png docs/images/hud-editor.png
	cp build/screens/hud-blocks.png docs/images/hud-blocks.png
	cp build/screens/dash-editor.png docs/images/dash-editor.png
	cp build/screens/view-editor.png docs/images/view-editor.png
	cp build/screens/data.png docs/images/data.png
	cp build/screens/elements.png docs/images/elements.png
	cp build/screens/dashboard-portrait.png docs/images/dashboard-portrait.png

clean:
	rm -rf build
