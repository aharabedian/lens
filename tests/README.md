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

Pure modules are tested on their own; features end to end, through `lens-hub` on the mocks.

| File | Covers |
|---|---|
| `test_units.lua` | `metrics` and `codec` on their own |
| `test_hub.lua` | The hub's pure modules on their own: `store` (and its metric list), `query`, `rules`, `alerts` (and its history), `format` (templates, dots), `config` (views, HUD blocks, resolution), `explore`, `viewdraft`, and the resolution that fits a screen |
| `test_net.lua` | Agents and the hub over `mocks/net.lua`: discovery, parts, lost packets, staleness, restarts, tokens, rules |
| `test_dashboard.lua` | The dashboard end to end with a PRISM-like agent: panels, alerts and acks by touch, stale nodes, beeps, GPU calls per quiet second, tier 2, config errors, fitting a 3 × 4 screen |
| `test_hud.lua` | The HUD on one terminal (`mocks/glasses.lua`): strip, bars, alerts, nothing overlapping, only changed setters, options, blocks from nine anchors with bar / text / gap / alerts, in `lens-hub` (calls per minute), a broken terminal |
| `test_huds.lua` | A HUD per terminal with its wearer's settings (`huds`), presets, and the HUD editor through `lens-hub`: presets, blocks, elements, anchors, nudges, only the tapping player, saved in `lens-board.cfg`, timing out, long lists, tier 2 and 3 × 4 screens |
| `test_board.lua` | `lens-board.cfg` (`board`): the library, overrides, renames, deletes, undo, pages, migration from `lens-hud.cfg` and 0.2.0's panels; the EDIT page and view editor through `lens-hub`: typing, pasting, preview, order, remove, `editors`, no keyboard |
| `test_elements.lua` | What a view can show, through `lens-hub`: state dots, several values in one line, `when`, on the dashboard, in the HUD and in the view editor (tier 2 too) |
| `test_pages.lua` | The dashboard's pages and the alert log through `lens-hub`: + PAGE named on the keyboard, panels per page, tabs, deleting a page, LOG now and earlier, a 3 × 4 screen |
| `test_data.lua` | The DATA page through `lens-hub`: metrics, series, filters, functions, SAVE AS PANEL, ADD TO MY HUD, counters as rates, `editors`, paging, narrow screens |
| `test_discover.lua` | `lens-discover`: listing, the report file, basics, filtering, `--widgets`, `--events`, `--glasses-test` |
| `test_setup.lua` | `lens-setup` with scripted answers: finding a PRISM router, its panels and HUD bar, the file (loads, comments, `lens-hub` runs it), `.shrc`, re-runs keeping edits, PRISM's port refused, no agents, no network card, no glasses, cancelling, a broken file |
| `test_update.lua` | `lens-update`: releases, main, branches, forks, keeping `lens-hub.cfg`, refusing broken downloads |
| `test_layout.lua` | `manifest.lua` lists every file; one version; no `utf8` in `src/` and `lib/`; every module names itself in its header; **dependencies point one way** (the rules in [architecture.md](../docs/architecture.md#modules)) |
| `hubrun.lua` | Runs `lens-hub` for feature tests: agents (`R.agent`), Glasses Terminals, a keyboard, a script of events, `R.tap` / `R.keys` / `R.paste` / `R.queue` |
| `helper.lua` | Shared setup (`H`): `check`, `run`, `screen` and `glasses` dumps for `make screens` |
| `mocks/oc.lua` | OpenOS `serialization`, `computer`, `event`, `component` (GPU, screen shape, modem, others by type), `unicode`, `filesystem`, `internet`, `math.random` as the game's, and a screen tests can read |
| `mocks/glasses.lua` | A Glasses Terminal and its widget objects, as `lens-discover` saw them; records what setters get |
| `mocks/net.lua` | Several computers' modems in one test, with packet loss and OpenComputers' packet limits |

## Writing a test

```lua
-- test_example.lua: one line saying what this covers.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")          -- the mock world
H.check(1 + 1 == 2, "what this shows, in words")
H.done()
```

Programs run with `H.run("lens-hub.lua", ...)`, driven by `M.onPull` (return an event, or nil to let time pass).
For `lens-hub` features, use `tests/hubrun.lua`:

```lua
local R = require("hubrun")(H)
local power = R.agent{ node = "power-room", role = "lumen", setup = function(m) m:gauge("lumen_fill_ratio", "f"):set(0.9) end }
local ok, err, dir = R.run{ cfg = "return { ... }", agents = { power }, keyboard = true, script = function(t)
  if t < 3 then return nil end             -- let it start
  return R.tap(" EDIT ", "Steve", 1)       -- or another event, or "stop"
end }
```

Screen tests find text with `M.find`, tap it and check what's drawn; HUD tests read the widgets from a
`require("glasses").new()` mock. A screen worth looking at gets `H.screen("name")` (`make screens`).
