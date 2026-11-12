# Tests

Every program runs unmodified against mocks: OpenComputers and OpenOS (`mocks/oc.lua`), several computers on one
network (`mocks/net.lua`) and OC Glasses' Glasses Terminal (`mocks/glasses.lua`). The mocks follow what's been
seen in game; [docs/architecture.md](../docs/architecture.md#whats-verified-in-game) says what's confirmed.

```
lua5.3 tests/run.lua            # everything
lua5.3 tests/run.lua hud        # files whose name contains "hud"
lua5.3 tests/run.lua -v         # print every check
make screens                    # also render the screens and HUDs the tests draw, to build/screens/*.png
```

Each `test_*.lua` runs in its own interpreter; the runner exits non-zero on any failure.

## Files

| File | Covers |
|---|---|
| `test_units.lua` | `metrics` and `codec` on their own |
| `test_hub.lua` | `store`, `query`, `rules`, `alerts` on their own |
| `test_net.lua` | Agents and the hub over `mocks/net.lua`: discovery, parts, lost packets, staleness, restarts, tokens, rules |
| `test_dashboard.lua` | `lens-hub` end to end on the mock screen with an agent on `mocks/net.lua`: panels, alerts and acks by touch, stale nodes, beeps, GPU calls per quiet second, tier 2, config errors |
| `test_discover.lua` | `lens-discover`: listing, the report file, basics, filtering, `--widgets`, `--events`, `--glasses-test` |
| `test_hud.lua` | The HUD on `mocks/glasses.lua`: strip, bars, alerts, nothing overlapping, only changed setters, options, in `lens-hub` (calls per minute), a broken terminal. Previews with `make screens` (`tools/render_hud.py`) |
| `test_update.lua` | `lens-update`: releases, main, branches, forks, keeping `lens-hub.cfg`, refusing broken downloads |
| `test_layout.lua` | `manifest.lua` lists every file; one version; no `utf8` in `src/` and `lib/` |
| `mocks/oc.lua` | OpenOS `serialization`, `computer`, `event`, `component` (GPU, modem, others by type), `unicode`, `filesystem`, `internet`, `math.random` as the game's, and a screen tests can read |
| `mocks/glasses.lua` | A Glasses Terminal and its widget objects, as `lens-discover` saw them; records what setters get |
| `mocks/net.lua` | Several computers' modems in one test, with packet loss and OpenComputers' packet limits |
| `test_setup.lua` | `lens-setup` with scripted answers: finding a PRISM router, its panels and HUD bar, the file (loads, comments, `lens-hub` runs it), `.shrc`, re-runs keeping edits, PRISM's port refused, no agents, no network card, no glasses, cancelling, a broken file |
| `helper.lua` | Shared setup (`H`): `check`, `run`, `screen` and `glasses` dumps for `make screens` |

## Writing a test

```lua
-- test_example.lua: one line saying what this covers.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")          -- the mock world
H.check(1 + 1 == 2, "what this shows, in words")
H.done()
```

Programs run with `H.run("lens-hub.lua", ...)`, driven by `M.onPull` (return an event, or nil to let time pass).
Screen tests find text with `M.find`, tap it with a `touch` event and check what's drawn; HUD tests read the
widgets from a `require("glasses").new()` mock.
