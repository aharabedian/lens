# Contributing

## Setup

- **Lua 5.3** (`lua5.3`). Debian/Ubuntu: `sudo apt install lua5.3`. macOS: `brew install lua@5.3`.
- A C compiler, `make`, `curl` and Python 3, then **`make dev`** ([tools/setup-dev.sh](tools/setup-dev.sh))
  installs luacheck into `.luarocks/` and a venv with Pillow (for `make screens`) into `.venv/`, without sudo.
  The Makefile falls back to `luacheck` and `python3` on the PATH.
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
- **One job per module**, its header comment its interface. Pages draw; editors hold state and actions; the app
  wires them (`docs/architecture.md`). If a file starts doing two things, split it.
- 2-space indent, `local` everything, short functions, a comment saying *why* when it isn't obvious.

## Docs move with code

| You changed | Update |
|---|---|
| Telemetry messages, metric rules | `docs/telemetry.md` |
| The query language | `docs/queries.md` and the header of `lib/lens/hub/query.lua` |
| Hub settings, the screen, the HUD | `docs/hub.md`, `config/lens-hub.example.cfg`, and `lib/lens/setup/` if `lens-setup` should write it |
| Install, setup steps, hardware | `docs/setup.md` |
| A new error or something easy to get wrong | `docs/troubleshooting.md` |
| Tests | `tests/README.md` |
| A module added, moved or depending on a new one | `docs/architecture.md` (the map and the dependency rules), `manifest.lua`, the rules in `tests/test_layout.lua` if a layer changes |
| Behavior, modules, programs, verified game APIs | `docs/architecture.md` |
| Anything a player would notice | `CHANGELOG.md` (Unreleased) |
