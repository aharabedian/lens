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
| `lens.hub.core` | hub | The above together, without screens or an event loop: `receive(data, from, now)` → replies, `tick(now)` → alert changes, `query`, `health` |

Dependencies point one way: `hub/*` → `codec`; `metrics` and `codec` don't know about the hub.

An agent's loop, in short:

```lua
local m   = metrics.new{ role = "power", clock = computer.uptime }
local enc = codec.encoder{ node = cfg.node, role = "power", boot = math.random(1, 2^31 - 1), interval = 10, token = cfg.token }
-- once, and on hello:   for _, p in ipairs(enc:describe(m:describe())) do modem.broadcast(port, p) end
-- every interval:       m:beginCycle(); <set gauges, add counters, raise alerts>;
--                       for _, p in ipairs(enc:snapshot(m:snapshot())) do modem.broadcast(port, p) end
```

The hub's loop: broadcast `hub:hello()` at start; for each `modem_message`, `hub:receive(data, from, now)` and
send its replies; about once a second, `hub:tick(now)` and redraw what changed.

## Tests

| File | Covers |
|---|---|
| `test_units.lua` | `metrics` and `codec` on their own |
| `test_hub.lua` | `store`, `query`, `rules`, `alerts` on their own |
| `test_net.lua` | Agents and the hub over `mocks/net.lua`: discovery, parts, lost packets, staleness, restarts, tokens, rules |
| `test_layout.lua` | `manifest.lua` lists every file |
| `mocks/oc.lua` | OpenOS `serialization`, `computer.uptime` |
| `mocks/net.lua` | Several computers' modems in one test, with packet loss and OpenComputers' packet limits |

## What's verified in game

The tests run against the mocks. This table says which of their behaviors we've confirmed in game.

| Assumption | Status |
|---|---|
| `serialization.serialize` output is no larger than the mock's (the mock writes every key in full) | **Unverified** |
| `modem.maxPacketSize()` is 8192, so 7 KB messages fit | **Unverified** (PRISM assumes the same) |
| A packet's size is the sum of its values: string length (min 1), number 8, boolean/nil 4; over the limit raises `packet too big`; at most 8 values | **Unverified** |
| `modem_message` event: `localAddress, remoteAddress, port, distance, ...values` | **Unverified** (PRISM relies on it) |
