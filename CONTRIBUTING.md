# Contributing

## Setup

- **Lua 5.3** (`lua5.3`). Debian/Ubuntu: `sudo apt install lua5.3`. macOS: `brew install lua@5.3`.
- A C compiler, `make` and `curl`, then **`make dev`** ([tools/setup-dev.sh](tools/setup-dev.sh)) installs
  luacheck into `.luarocks/` without sudo. The Makefile falls back to `luacheck` on the PATH.
- On Windows, use WSL; the test runner shells out to `ls`, `mkdir` and `rm`.

## Workflow

1. Write or change a test in `tests/` that shows the behavior you want.
2. Change the code.
3. `make check` (lint + tests) must pass. CI runs the same on every push and pull request.
4. Update the docs in the same change (table below).
5. If you tried it in game, say so in the PR and update the verification table in `docs/architecture.md`.

## Code conventions

- **Target OpenComputers' Lua 5.3.** No 5.4-only features. Use OpenOS's `unicode`, not `utf8`.
- **Don't block.** Programs keep yielding (`event.pull*`) between steps.
- **Wireless packets are about 8 KB.** Split or trim; never send unbounded data.
- **Telemetry changes add fields; they don't rename them**, so agents and hub can be versions apart.
- **No state at module load** (OpenOS caches modules); keep state in the objects a module returns.
- 2-space indent, `local` everything, short functions, a comment saying *why* when it isn't obvious.

## Docs move with code

| You changed | Update |
|---|---|
| Telemetry messages, metric rules | `docs/telemetry.md` |
| Behavior, modules, verified game APIs | `docs/architecture.md` |
| Anything a player would notice | `CHANGELOG.md` (Unreleased) |
