# Architecture

Agents push lens/1 messages ([telemetry.md](telemetry.md)); the hub listens. Each module's header comment
is its interface; this page is the map.

## Modules

| Module | Used by | Does |
|---|---|---|
| `lens.metrics` | agents | Registry of gauges, counters, alerts and health for one node. Produces `describe` and `snapshot` bodies. Pure |
| `lens.codec` | agents, hub | Envelope, splitting messages into packets of at most 7 KB, decoding with token and proto checks, joining parts back together. Pure apart from OpenOS `serialization` |
| `lens.hub.store` | hub | Per node: descriptors, the latest series, counter rates, health, staleness. Asks for a `hello` when a snapshot's descriptors are missing |
| `lens.hub.query` | hub | The selector language ([queries.md](queries.md)), compiled to a function of a lookup |
| `lens.hub.rules` | hub | The hub's own alerts: queries that must stay true for `for` seconds |
| `lens.hub.alerts` | hub | One list of every active alert: dedupe by `node/id`, since, acks, ordering |
| `lens.hub.config` | hub | `/home/lens-hub.cfg`: defaults and checks, with readable errors ([hub.md](hub.md)) |
| `lens.hub.dashboard` | hub | The screen: builds a frame of rows from a model, sends the GPU only the segments that changed, touch targets |
| `lens.hub.format` | hub | A view's value as text, bar fraction and color level (`format`, `color`): the same on the dashboard and the HUD. Pure |
| `lens.hub.huds` | hub | One `lens.hub.hud` per Glasses Terminal, with its wearer's blocks (`/home/lens-hud.cfg`, written only here) or `hud` from the config; elements name views by label; the HUD editor's changes |
| `lens.hub.hud` | hub | Draws HUD blocks (bar, text, alerts, gap elements, placed from nine anchors) as widgets on one Glasses Terminal; made once, setters called only on change, calls counted |
| `lens.hub.app` | hub | The program's state: hub core + panels (values, history) + dashboard; reacts to packets, touches and ticks |
| `lens.setup.hub` | lens-setup | The steps: hub, agents and their standard panels, HUD, start on boot; review and save |
| `lens.setup.input`, `lens.setup.render` | lens-setup | Questions on the terminal; `lens-hub.cfg` as commented Lua |
| `lens.files` | setup | Reading files, atomic writes, `.bak` |
| `lens.discover` | lens-discover | Components, their methods and docs as report lines (pure over OpenOS `component`) |
| `lens.gui` | hub | GPU primitives and the palette (adapted from PRISM's) |
| `lens.hub.core` | hub | The above together, without screens or an event loop: `receive(data, from, now)` → replies, `tick(now)` → alert changes, `query`, `health` |

Dependencies point one way: programs → `hub/*`, `setup/*` → `codec`, `gui`, `files`. `setup/*` reads the hub's
`config` (to check what it writes) but nothing else of the hub's; `metrics` and `codec` don't know about either.

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
| `lens-hub.lua` | The hub: the event loop around `lens.hub.app` (packets, touches, a tick a second) |
| `lens-setup.lua` | Guided setup: writes `/home/lens-hub.cfg` (and `/home/.shrc`), finding agents with a hello (`lens.setup.*`) |
| `lens-discover.lua` | Lists this computer's components with every method and doc string, into `/home/lens-discover.txt`: for designing against a mod's real API (`lens.discover`) |
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
| Widgets have no per-player methods (Text2D: get/set Alpha, Color, Position, Rotation, Scale, Text, Visible, getID; Rect2D: Alpha, Color, Position, Size, Visible, getID; Quad: Alpha, Color, Vertex, VertexCount, Visible, getID): a terminal shows the same HUD to everyone linked to it | **Seen in game** (`lens-discover --widgets`, 2026-11-12) |
| `getBindPlayers()` returns the linked players' names (the hub accepts a name, a list of names, or a list of tables with `name`; it uses it only at start, when it names exactly one player) | Assumed: the return shape hasn't been seen |
| `screen.getAspectRatio()` returns the multiblock screen's size in blocks; text is drawn as large as fits while keeping the resolution's shape, characters are twice as tall as wide, and a multiblock screen loses about 1/8 block of border at each edge (`resolution = "fit"`: 73 × 50 on 3 × 4) | Assumed: the border is an estimate; `{ width, height }` overrides |
| OpenOS's font has ↖ ↗ ↘ ↙ ◀ ▶ (the HUD editor's anchor grid and nudges) | Assumed |
| A `glasses_on` arrives for a player already wearing glasses when the hub starts | Assumed not: getBindPlayers covers it |
| Events (the hub uses `glasses_on`'s size to place the HUD by its anchor): `glasses_on(terminal, player, width, height)` (854x457 here, briefly 854x480), `glasses_off(terminal, player)`; clicking with glasses on sends nothing | **Seen in game** (`lens-discover --events`, 2026-11-12) |
| Colors 0..1 (`setColor(255, 0, 0)` clamps to the same red as `(1, 0, 0)`) | **Seen in game** (`--glasses-test`, 2026-11-12) |
| Positions are GUI pixels from the top left (at GUI scale 3, x 10 is 30 screen px); `glasses_on`'s width and height are the GUI size at that moment | **Seen in game** (`--glasses-test`, 2026-11-12) |
| Rect2D `setSize(a, b)` makes it `b` wide and `a` tall: **height first** | **Seen in game** twice (60, 14 drew 14 x 60; 10, 80 drew 80 x 10) |
| Text without a `setScale` call is at scale 2; at scale s a character is about 5.2 * s px wide (measured at 0.5 and 2). `setScale(2)` looked like it did nothing only because 2 is the default | **Seen in game** (`--glasses-test`, 2026-11-12, twice) |
| `math.random(m, n)` doesn't return an integer (the mock gives floats) | **Seen in game**: PRISM crashed on it. Use `codec.newBoot()` |
| `serialization.serialize` output is no larger than the mock's (the mock writes every key in full) | **Unverified**; a one-router base's snapshots arrived fine (2026-11-12), but splitting into parts hasn't been exercised in game |
| `modem.maxPacketSize()` is 8192, so 7 KB messages fit | **Unverified** (PRISM assumes the same) |
| A packet's size is the sum of its values: string length (min 1), number 8, boolean/nil 4; over the limit raises `packet too big`; at most 8 values | **Unverified** |
| `modem_message` event: `localAddress, remoteAddress, port, distance, ...values` | **Reported working** (2026-11-12): hub heard a PRISM router; backlog, machine states and a machine-down alert showed on the dashboard |
| `touch` event: `screenAddress, x, y, button, player` | **Reported working** (2026-11-12): tapping an alert and ACK ALL acknowledge |
| The block characters `▁`–`▇`, `●`, `✓`, `–` draw on an OpenComputers screen | **Reported working** (2026-11-12): bars, sparklines and symbols look right |
