# CLAUDE.md

Guidance for Claude Code working in this repo. Keep it short and current; details live in `docs/`.

## What this is

**LENS** (Live Engineering & Network Status): base-wide monitoring for GregTech: New Horizons on OpenComputers.
Agents (PRISM in `../prism`, a power monitor, ...) push health, metrics and alerts over wireless; the hub
collects them and drives a dashboard screen and an AR glasses HUD (OC Glasses). `lens-setup` writes the hub's config.
The telemetry format in `docs/telemetry.md` is the contract between agents and hub; change it deliberately.

## Commands

```
make check                        # lint + all tests: run before every commit
lua5.3 tests/run.lua [filter]     # tests (add -v for every check)
luacheck .                        # lint
make screens                      # render the screens tests draw to PNGs (Python + Pillow)
```

## Rules

- **Test first.** Every behavior change gets a check in `tests/`. Screen changes get a screen test (find
  text, tap it, assert what's drawn). Never mark work done without `make check` passing.
- **Mocks mirror the game.** Test mocks encode our understanding of OpenComputers / GregTech / glasses APIs.
  Probe in game (`lens-discover`) before designing against an API; when the user reports in-game behavior that
  differs, fix the mock first, then the code, and update the verification table in `docs/architecture.md`.
- **Runtime constraints (OpenComputers):** Lua 5.3, no 5.4 features, OpenOS `unicode` instead of `utf8`;
  never block without yielding; wireless packets are ~8 KB; GPU and glasses calls are rationed, so update
  only what changed.
- **Agents never depend on the hub.** The hub observes; agents keep working without it.
- **Observability, not control.** No commands from the hub back to agents (decided: scope creep, the player
  walks over). LENS has its own port and token, isolated from each agent's own network.
- **Telemetry changes add fields rather than renaming them.**
- **Keep logic pure where it can be** (metrics, codec, query, store, alerts) and unit-test it.
- **Config:** only `lens-setup` writes `lens-hub.cfg` (after showing it, keeping a `.bak` and hand edits). A new
  setting gets a default in `lib/lens/hub/config.lua` and a row in `docs/hub.md`.
- **Releases:** `lib/lens/version.lua` and `VERSION` in `src/lens-update.lua` move together (a test checks).
- A new file in `src/` or `lib/` goes in `manifest.lua` (a test checks).
- **Docs move with code**, in the same change (table in `CONTRIBUTING.md`). Tables over prose; link, don't repeat.

## Layout

```
src/        programs: lens-hub.lua, lens-setup.lua, lens-discover.lua, lens-update.lua (self-contained)
lib/lens/   modules: metrics, codec (agents + hub), gui, files, discover, hub/, setup/
manifest.lua  every file lens-update installs
config/     lens-hub.example.cfg
docs/       setup, hub, queries, troubleshooting, telemetry (the protocol), architecture, images/
tests/      run.lua, helper.lua, mocks/{oc,net,glasses}.lua, test_*.lua (README.md)
tools/      setup-dev.sh, render_screens.py, render_hud.py
```
