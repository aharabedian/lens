# CLAUDE.md

Guidance for Claude Code working in this repo. Keep it short and current; details live in `docs/`.

## What this is

**LENS** (Live Engineering & Network Status): base-wide monitoring for GregTech: New Horizons on OpenComputers.
Agents (PRISM in `../prism`, a power monitor, ...) push health, metrics and alerts over wireless; the hub
collects them and drives a dashboard screen and an AR glasses HUD. Early stage: see the roadmap in `README.md`.
The telemetry format in `docs/telemetry.md` is the contract between agents and hub; change it deliberately.

## Commands

```
make check                        # lint + all tests: run before every commit
lua5.3 tests/run.lua [filter]     # tests (add -v for every check)
luacheck .                        # lint
```

## Rules

- **Test first.** Every behavior change gets a check in `tests/`. Never mark work done without `make check` passing.
- **Mocks mirror the game.** Test mocks encode our understanding of OpenComputers / GregTech / glasses APIs.
  Probe in game before designing against an API; don't present unverified API assumptions as fact.
- **Runtime constraints (OpenComputers):** Lua 5.3, no 5.4 features, OpenOS `unicode` instead of `utf8`;
  never block without yielding; wireless packets are ~8 KB; GPU and glasses calls are rationed, so update
  only what changed.
- **Agents never depend on the hub.** The hub observes; agents keep working without it.
- **Telemetry changes add fields rather than renaming them.**
- **Keep logic pure where it can be** (metrics, codec, query, store, alerts) and unit-test it.
- A new file in `src/` or `lib/` goes in `manifest.lua` (a test checks).
- **Docs move with code**, in the same change (table in `CONTRIBUTING.md`). Tables over prose; link, don't repeat.

## Layout

```
src/        programs
lib/lens/   modules
manifest.lua  every file the updater installs
docs/       telemetry spec, architecture
tests/      run.lua, helper.lua, test_*.lua
tools/      setup-dev.sh
```
