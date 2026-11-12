# Architecture

Agents push lens/1 messages ([telemetry.md](telemetry.md)); the hub listens. Each module's header comment
is its interface; this page is the map.

## Modules

| Module | Used by | Does |
|---|---|---|
| `lens.metrics` | agents | Registry of gauges, counters, alerts and health for one node. Produces `describe` and `snapshot` bodies. Pure |
| `lens.codec` | agents, hub | Envelope, splitting messages into packets of at most 7 KB, decoding with token and proto checks, joining parts back together. Pure apart from OpenOS `serialization` |

An agent's loop, in short:

```lua
local m   = metrics.new{ role = "power", clock = computer.uptime }
local enc = codec.encoder{ node = cfg.node, role = "power", boot = math.random(1, 2^31 - 1), interval = 10, token = cfg.token }
-- once, and on hello:   for _, p in ipairs(enc:describe(m:describe())) do modem.broadcast(port, p) end
-- every interval:       m:beginCycle(); <set gauges, add counters, raise alerts>;
--                       for _, p in ipairs(enc:snapshot(m:snapshot())) do modem.broadcast(port, p) end
```

## What's verified in game

The tests run against `tests/mocks/oc.lua`. This table says which of its behaviors we've confirmed in game.

| Assumption | Status |
|---|---|
| `serialization.serialize` output is no larger than the mock's (the mock writes every key in full) | **Unverified** |
| `modem.maxPacketSize()` is about 8 KB, so 7 KB messages fit | **Unverified** (PRISM assumes the same) |
