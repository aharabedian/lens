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
| `lens.hub.app` | hub | The program's state: hub core + panels (values, history) + dashboard; reacts to packets, touches and ticks |
| `lens.discover` | lens-discover | Components, their methods and docs as report lines (pure over OpenOS `component`) |
| `lens.gui` | hub | GPU primitives and the palette (adapted from PRISM's) |
| `lens.hub.core` | hub | The above together, without screens or an event loop: `receive(data, from, now)` → replies, `tick(now)` → alert changes, `query`, `health` |

Dependencies point one way: programs → `hub/*` → `codec`, `gui`; `metrics` and `codec` don't know about the hub.

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
| `lens-discover.lua` | Lists this computer's components with every method and doc string, into `/home/lens-discover.txt`: for designing against a mod's real API (`lens.discover`) |
| `lens-update.lua` | Installs and updates from GitHub what `manifest.lua` lists. Self-contained: it installs the modules |

Each program but `lens-update` starts with the same three lines as PRISM's: add `/home/lib/?.lua` to the path,
forget cached `lens.*` modules, and say "run lens-update" if they're missing.

## Tests

| File | Covers |
|---|---|
| `test_units.lua` | `metrics` and `codec` on their own |
| `test_hub.lua` | `store`, `query`, `rules`, `alerts` on their own |
| `test_net.lua` | Agents and the hub over `mocks/net.lua`: discovery, parts, lost packets, staleness, restarts, tokens, rules |
| `test_dashboard.lua` | `lens-hub` end to end on the mock screen with an agent on `mocks/net.lua`: panels, alerts and acks by touch, stale nodes, beeps, GPU calls per quiet second, tier 2, config errors |
| `test_discover.lua` | `lens-discover`: listing, the report file, basics, filtering |
| `test_update.lua` | `lens-update`: releases, main, branches, forks, keeping `lens-hub.cfg`, refusing broken downloads |
| `test_layout.lua` | `manifest.lua` lists every file; one version |
| `mocks/oc.lua` | OpenOS `serialization`, `computer`, `event`, `component` (GPU, modem), `unicode`, `filesystem`, `internet`, and a screen tests can read |
| `mocks/net.lua` | Several computers' modems in one test, with packet loss and OpenComputers' packet limits |

## What's verified in game

The tests run against the mocks. This table says which of their behaviors we've confirmed in game.

| Assumption | Status |
|---|---|
| `math.random(m, n)` doesn't return an integer (the mock gives floats) | **Seen in game**: PRISM crashed on it. Use `codec.newBoot()` |
| `serialization.serialize` output is no larger than the mock's (the mock writes every key in full) | **Unverified**; a one-router base's snapshots arrived fine (2026-11-12), but splitting into parts hasn't been exercised in game |
| `modem.maxPacketSize()` is 8192, so 7 KB messages fit | **Unverified** (PRISM assumes the same) |
| A packet's size is the sum of its values: string length (min 1), number 8, boolean/nil 4; over the limit raises `packet too big`; at most 8 values | **Unverified** |
| `modem_message` event: `localAddress, remoteAddress, port, distance, ...values` | **Reported working** (2026-11-12): hub heard a PRISM router; backlog, machine states and a machine-down alert showed on the dashboard |
| `touch` event: `screenAddress, x, y, button, player` | **Reported working** (2026-11-12): tapping an alert and ACK ALL acknowledge |
| The block characters `▁`–`▇`, `●`, `✓`, `–` draw on an OpenComputers screen | **Reported working** (2026-11-12): bars, sparklines and symbols look right |
