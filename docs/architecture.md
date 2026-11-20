# Architecture

Agents push lens/1 messages ([telemetry.md](telemetry.md)); the hub listens. Each module's header comment
is its interface; this page is the map.

## Modules

Each module's header comment is its interface; this table is the map, by layer. `tests/test_layout.lua` checks
that every module's header names it and that dependencies only point the ways listed below.

| Layer | Module | Does |
|---|---|---|
| **Protocol** (agents vendor these) | `lens.metrics` | Registry of gauges, counters, alerts and health for one node; produces `describe` and `snapshot` bodies. Pure |
| | `lens.codec` | Envelope, splitting messages into packets of at most 7 KB, decoding with token and proto checks, joining parts. Pure apart from OpenOS `serialization` |
| **Hub core** (pure) | `lens.hub.store` | Per node: descriptors, the latest series, counter rates, health, staleness, restarts (a new `boot`); the list of metrics there is to query; nodes remembered from earlier runs. Asks for a `hello` when a snapshot's descriptors are missing |
| | `lens.hub.query` | The selector language ([queries.md](queries.md)), compiled to a function of a lookup |
| | `lens.hub.rules` | The hub's own alerts: queries that must stay true for `for` seconds |
| | `lens.hub.alerts` | One list of every active alert: dedupe by `node/id`, since, acks, ordering; the last 100 that ended (LOG) |
| | `lens.hub.core` | The above together: `receive(data, from, now, distance)` → replies, `tick(now)` → alert changes, `query`, `lookup`, `metrics`, `health`; per node, snapshots whole and cut short and the distance (`traffic`), `forget` |
| **Views** (pure) | `lens.hub.format` | A view's value as text, bar fraction and color level (`format`, `color`): the same on the dashboard and the HUD |
| | `lens.hub.timeline` | The LOG page's timeline: a node's worst alert in each column of the last 12 or 24 hours, restarts as marks, and the hour labels |
| | `lens.hub.inspect` | What a view's query comes to on the panel page: its function calls, each replaced by its value, the metrics it reads; low / average / high of a history |
| | `lens.hub.explore` | Building a query by tapping: a metric, label filters, a function → query text |
| | `lens.hub.viewdraft` | A view being edited: fields as text, status rules and dot states as rows, focus and cursor, back to a checked view |
| | `lens.hub.ruledraft` | An alert rule being typed on the screen: its fields, the cursor, back to a checked rule |
| | `lens.hub.textfield` | One line being typed, with a cursor (insert, ← → Home End, Backspace, Delete, pastes, a length limit): used by viewdraft and the editors' renames |
| **Settings and state** | `lens.hub.config` | `/home/lens-hub.cfg`: defaults and checks, readable errors ([hub.md](hub.md)); views, HUD blocks |
| | `lens.hub.clock` | Real time (seconds since 1970) from a file's modification time, read once an hour and carried on with uptime |
| | `lens.hub.logbook` | `/home/lens-log.cfg`: the alert log kept across restarts (alerts that ended, lens-hub starting and stopping), newest first, in real time |
| | `lens.hub.mutes` | Muted nodes and alerts: for a time or until they clear; which mute covers an alert. Only what the hub shows and beeps changes |
| | `lens.hub.board` | `/home/lens-board.cfg`: the view library (lens-hub.cfg's views with screen edits over them, plus new ones), the dashboard's pages and their panels, players' HUD presets; undo |
| | `lens.hub.huds` | One `lens.hub.hud` per Glasses Terminal with its wearer's blocks (kept by the board) or the config's `hud` |
| | `lens.hub.hud` | Draws HUD blocks (bar, text, alerts, gap; nine anchors) as widgets on one terminal; setters only on change, calls counted |
| **Editors** | `lens.hub.editors.<kind>` | One per editor: `hud` (a player's HUD presets), `edit` (the dashboard's pages, their panels, the library), `view` (one view's fields), `data` (queries by tapping), `log` (the alert log, read-only), `panel` (one panel up close), `node` (one agent up close), `rule` (alerts made on the screen). Each has `actions(app, a, mine)` and `model(app, e, now)`, and `key` / `paste` if it takes typing; state and actions only, no drawing |
| **Screen** | `lens.hub.frame` | One screenful being built (row segments, touch targets) and the widgets pages share |
| | `lens.hub.pages.<kind>` | One per page: `main` (the dashboard, with page tabs), `glance` (glance mode) and one per editor. `draw(f, model, actions)`; drawing only |
| | `lens.hub.dashboard` | Picks the page for the model, then sends the GPU only the rows or segments that changed; touch dispatch |
| **Program** | `lens.hub.app` | The hub program's state: core, board, HUDs, panels and their history, the one open editor; reacts to packets, touches, keys and ticks |
| **Setup** | `lens.setup.hub`, `.input`, `.render` | `lens-setup`'s steps, questions on the terminal, `lens-hub.cfg` as commented Lua |
| **Shared** | `lens.gui` | GPU primitives, the palette (the SPECTRA logo's, LENS blue as the accent), the resolution that fits a screen's shape |
| | `lens.splash` | The SPECTRA logo in pixel art while `lens-hub` starts: `show(gpu, w, h, name, version, accent)`; `rows(scale)` is pure |
| | `lens.files` | Reading files, atomic writes, `.bak` |
| | `lens.discover` | Components, their methods and docs as report lines (`lens-discover`) |

**Dependencies point one way:** programs → `hub.app` → editors, `dashboard` → pages → `frame` → `gui`.
Pages only draw (`gui`, `frame`); editors never draw; nothing but the program uses the app; `setup/*` reads
the hub's `config` and nothing else of it; `metrics` and `codec` need nothing of LENS (agents copy them).

### Files on the hub

| File | Written by | Holds |
|---|---|---|
| `/home/lens-hub.cfg` | `lens-setup` and you | Network, the views and HUD to start from, rules, `editors` |
| `/home/lens-board.cfg` | `lens-hub` only | What's changed on the screen: views, the dashboard's pages, each player's HUDs; the nodes the hub has heard; mutes; alert rules made on the screen |
| `/home/lens-log.cfg` | `lens-hub` only | The alert log (LOG): the last 300 entries, saved once a minute and on stop |
| `/home/.lens-clock` | `lens-hub` only | Nothing: written once an hour to read the real time back from its modification time |

### Adding an editor

1. `lib/lens/hub/editors/<kind>.lua`: its state, `actions` (a button in another page opens it with
   `app:open(kind, player, state)`) and `model`.
2. `lib/lens/hub/pages/<kind>.lua`: `draw(f, model, actions)`.
3. Register it in `EDITORS` (`lens.hub.app`) and `PAGES` (`lens.hub.dashboard`), and add both to `manifest.lua`.
4. A test driving it through `lens-hub` with `tests/hubrun.lua`; screenshots with `H.screen`.

An agent's loop, in short:

```lua
local m   = metrics.new{ role = "power", clock = computer.uptime }
local enc = codec.encoder{ node = cfg.node, role = "power", boot = codec.newBoot(), interval = 10, token = cfg.token }
-- once, and on hello:   for _, p in ipairs(enc:describe(m:describe())) do modem.broadcast(port, p) end
-- every interval:       m:beginCycle(); <set gauges, add counters, raise alerts>;
--                       for _, p in ipairs(enc:snapshot(m:snapshot())) do modem.broadcast(port, p) end
```

## Programs

| Program (`src/`) | Does |
|---|---|
| `lens-hub.lua` | The hub: the event loop around `lens.hub.app` (packets, touches, keys, pastes, glasses, a tick a second); picks the resolution |
| `lens-setup.lua` | Guided setup: writes `/home/lens-hub.cfg` (and `/home/.shrc`), finding agents with a hello (`lens.setup.*`) |
| `lens-discover.lua` | Lists this computer's components with every method and doc string, into `/home/lens-discover.txt`: for designing against a mod's real API (`lens.discover`). Probes: `--widgets`, `--events`, `--glasses-test`, `--redstone`, `--chat` |
| `lens-update.lua` | Installs and updates from GitHub what `manifest.lua` lists. Self-contained: it installs the modules |

Each program but `lens-update` starts with the same three lines as PRISM's: add `/home/lib/?.lua` to the path,
forget cached `lens.*` modules, and say "run lens-update" if they're missing.

## Tests

The tests run every program unmodified against mocks of OpenComputers, the network and OC Glasses:
[tests/README.md](../tests/README.md).

## What's verified in game

The tests run against the mocks. This table says which of their behaviors we've confirmed in game.

| Assumption | Status |
|---|---|
| OC Glasses' Glasses Terminal is component `glasses` with: `addTextLabel`, `addRect`, `addQuad`, `addDot`, `addTriangle`, `addItem` (2D), `addCube3D`, `addDot3D`, `addFloatingText`, `addLine3D`, `addQuad3D`, `addTriangle3D` (3D), each taking no arguments and returning a widget object (`Text2D`, `Rect2D`...); `getBindPlayers`, `getObjectCount`, `newUniqueKey`, `removeAll`, `removeObject(id)`, `sendChatAs`, `sendMessageTo` | **Seen in game** (`lens-discover`, 2026-11-12). |
| Widget objects are tables of methods. All: `getID`, `set/getColor`, `set/getAlpha`, `setVisible`/`isVisible`. Text2D: `set/getPosition`, `Scale`, `Rotation`, `Text`. Rect2D: `set/getPosition`, `Size`. Quad2D, Triangle2D: `setVertex`, `getVertexCount`. Dot2D: `Position`, `Scale`. ItemIcon: `Position`, `Scale`, `Rotation`, `Item`. `removeObject(getID())` removes one | **Seen in game** (`lens-discover --widgets`, 2026-11-12) |
| Widgets live in the Glasses Terminal, not the computer: they stay (frozen) after a crash or the computer switching off, and a restarted hub drew a second HUD beside them. `removeAll()` removes every widget on the terminal | Widgets staying: **reported in game** (2026-11-18). That `removeAll()` clears them: assumed (`lens-discover` uses it on its test widgets) |
| Widgets have no per-player methods (Text2D: get/set Alpha, Color, Position, Rotation, Scale, Text, Visible, getID; Rect2D: Alpha, Color, Position, Size, Visible, getID; Quad: Alpha, Color, Vertex, VertexCount, Visible, getID): a terminal shows the same HUD to everyone linked to it | **Seen in game** (`lens-discover --widgets`, 2026-11-12) |
| The Glasses Terminal's `sendMessageTo(player, text)` puts text in that player's chat only (alerts in chat; the argument order is a guess) | **Probe**: `lens-discover --chat <name>` sends three numbered tries in different argument orders; which arrive, and does anyone else linked to the terminal see them? |
| `getBindPlayers()` returns the linked players' names (the hub accepts a name, a list of names, or a list of tables with `name`; it uses it only at start, when it names exactly one player) | Assumed: the return shape hasn't been seen |
| `screen.getAspectRatio()` returns the multiblock screen's size in blocks; text is drawn as large as fits while keeping the resolution's shape, characters are twice as tall as wide, and a multiblock screen loses about 1/8 block of border at each edge (`resolution = "fit"`: 73 × 50 on 3 × 4) | **Reported working** (2026-11-12): a 3 × 4 screen is filled. The 1/8-block border is still our estimate; `{ width, height }` overrides |
| OpenOS's font has ↖ ↗ ↘ ↙ ◀ ▶ (the HUD editor's anchor grid and nudges) | **Seen in game** (2026-11-12) |
| Per-player HUDs on their own terminals; a wearer's HUD shows straight away after the hub restarts | **Reported working** (2026-11-12). Which of getBindPlayers or glasses_on did it isn't known |
| `key_down(keyboard, char, code, player)` and `clipboard(keyboard, text, player)` reach the hub from a keyboard attached to its screen; Insert pastes | **Reported working** (2026-11-12): typing and pasting in the view editor |
| A `glasses_on` arrives for a player already wearing glasses when the hub starts | Assumed not: getBindPlayers covers it |
| Logging out (or changing dimension) with glasses on sends `glasses_off`, and logging back in `glasses_on` (Welcome back) | **Probe**: run `lens-discover --events 600` on the hub, put the glasses on, log out, log back in, then read `/home/lens-discover.txt`. Without them, Welcome back shows only after taking the glasses off by hand |
| Events (the hub uses `glasses_on`'s size to place the HUD by its anchor): `glasses_on(terminal, player, width, height)` (854x457 here, briefly 854x480), `glasses_off(terminal, player)`; clicking with glasses on sends nothing | **Seen in game** (`lens-discover --events`, 2026-11-12) |
| `setAlpha` on a Rect2D can change every second (the new-alert flash) without flicker or lag | **Unverified**: alpha is set in game, but not changed this often yet |
| A redstone card's `setOutput(side, level)` (side from OpenOS `sides`) lights a lamp on that side; what the output does when `lens-hub` stops on an error (it sets 0 on the way out) and when the computer turns off (LUMEN saw a card drop to 0) | **Probe**: `lens-discover --redstone north`, then turn the computer off and on |
| Colors 0..1 (`setColor(255, 0, 0)` clamps to the same red as `(1, 0, 0)`) | **Seen in game** (`--glasses-test`, 2026-11-12) |
| Positions are GUI pixels from the top left (at GUI scale 3, x 10 is 30 screen px); `glasses_on`'s width and height are the GUI size at that moment | **Seen in game** (`--glasses-test`, 2026-11-12) |
| Rect2D `setSize(a, b)` makes it `b` wide and `a` tall: **height first** | **Seen in game** twice (60, 14 drew 14 x 60; 10, 80 drew 80 x 10) |
| Text without a `setScale` call is at scale 2; at scale s a character is about 5.2 * s px wide (measured at 0.5 and 2). `setScale(2)` looked like it did nothing only because 2 is the default | **Seen in game** (`--glasses-test`, 2026-11-12, twice) |
| `filesystem.lastModified(path)` returns real-world milliseconds (UTC), so the log keeps real times across restarts | **Seen in game by LUMEN** (2026-11-18, the same OpenOS call): not yet in LENS |
| `gpu.setResolution` can change while the program runs (glance mode drops to a third and back) | **Seen in game by LUMEN** (its big mode); not yet in LENS |
| `math.random(m, n)` doesn't return an integer (the mock gives floats) | **Seen in game**: PRISM crashed on it. Use `codec.newBoot()` |
| `serialization.serialize` output is no larger than the mock's (the mock writes every key in full) | **Unverified**; a one-router base's snapshots arrived fine (2026-11-12), but splitting into parts hasn't been exercised in game |
| `modem.maxPacketSize()` is 8192, so 7 KB messages fit | **Unverified** (PRISM assumes the same) |
| A packet's size is the sum of its values: string length (min 1), number 8, boolean/nil 4; over the limit raises `packet too big`; at most 8 values | **Unverified** |
| `os.sleep` (OpenOS) waits while yielding; `gpu.set` draws `▀` with the foreground on top (the splash's half-block pixels) | **Unverified** |
| `modem_message` event: `localAddress, remoteAddress, port, distance, ...values` | **Reported working** (2026-11-12): hub heard a PRISM router; backlog, machine states and a machine-down alert showed on the dashboard. The distance (the node page) hasn't been looked at in game |
| `touch` event: `screenAddress, x, y, button, player` | **Reported working** (2026-11-12): tapping an alert and ACK ALL acknowledge |
| The block characters `▁`–`▇`, `●`, `✓`, `–` draw on an OpenComputers screen | **Reported working** (2026-11-12): bars, sparklines and symbols look right |
