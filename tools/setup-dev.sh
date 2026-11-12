#!/usr/bin/env bash
# setup-dev.sh - install the development tools inside the repo, without sudo:
#   .luarocks/  LuaRocks + luacheck (for `make lint`)
#
# Needs lua5.3, a C compiler, make and curl. Safe to re-run; skips what's already there.
# Usage: tools/setup-dev.sh            (or: make dev)
set -euo pipefail

LUA_VERSION=5.3.6
LUAROCKS_VERSION=3.13.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need() { command -v "$1" >/dev/null || { echo "setup-dev: needs $1 ($2)" >&2; exit 1; }; }
need lua5.3 "Debian/Ubuntu: sudo apt install lua5.3"
need curl "Debian/Ubuntu: sudo apt install curl"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- luacheck
if [ -x .luarocks/bin/luacheck ]; then
  echo "luacheck: already in .luarocks/bin"
else
  need cc "Debian/Ubuntu: sudo apt install build-essential"
  need make "Debian/Ubuntu: sudo apt install build-essential"
  # LuaRocks compiles luafilesystem (a luacheck dependency) against the Lua headers. Use the system
  # ones if installed (liblua5.3-dev), else the headers from the official Lua source release.
  if [ -f /usr/include/lua5.3/lua.h ]; then
    LUA_INC=/usr/include/lua5.3
  else
    echo "luacheck: fetching Lua $LUA_VERSION headers"
    curl -fsSL "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" | tar xz -C "$WORK"
    LUA_INC="$WORK/lua-$LUA_VERSION/src"
  fi
  echo "luacheck: building LuaRocks $LUAROCKS_VERSION into .luarocks"
  curl -fsSL "https://luarocks.github.io/luarocks/releases/luarocks-$LUAROCKS_VERSION.tar.gz" | tar xz -C "$WORK"
  (
    cd "$WORK/luarocks-$LUAROCKS_VERSION"
    ./configure --prefix="$ROOT/.luarocks" --lua-version=5.3 \
      --with-lua-bin="$(dirname "$(command -v lua5.3)")" --with-lua-include="$LUA_INC" >/dev/null
    make >/dev/null && make install >/dev/null
  )
  .luarocks/bin/luarocks --tree "$ROOT/.luarocks" install luacheck
fi

echo ""
echo "done: make check (lint + tests)"
