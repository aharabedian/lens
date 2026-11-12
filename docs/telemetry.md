# Telemetry protocol (`lens/1`)

How agents (PRISM, the power monitor, ...) report to the LENS hub. Agents **push**; the hub listens,
picks what it shows, and never needs to know an agent's internals.

Each push carries three things:

- **Health**: the agent's own verdict: `ok`, `warn` or `bad`.
- **Metrics**: numbers with names and labels, in the style of Prometheus.
- **Alerts**: the problems the agent sees right now.

Agents never depend on the hub: if the hub is down, agents keep working and their pushes are simply not heard.

**LENS observes; it doesn't control.** Messages only flow from agents to the hub (apart from `hello`). There
are no commands back to agents: to stop a system, go to it. Its own UI (like PRISM's control screen) is
where control lives.

## Transport

| | |
|---|---|
| Medium | Wireless or wired network card, `modem.broadcast` on `lensPort` (default **4243**). Bases in several dimensions reach the hub through linked cards; the protocol is the same on every medium |
| Isolation | LENS is separate from each agent's own network: its own port and its own `token`, never PRISM's. An agent program that speaks both keeps them apart |
| Encoding | One OpenOS `serialization.serialize`d table per packet |
| Size | Packets are limited to about 8 KB (`modem.maxPacketSize()`). Each serialized message must stay **≤ 7 KB**, leaving headroom for the modem's own overhead |
| Auth | If a LENS `token` is configured, every message carries it, and the hub and agents drop messages without the same token |
| Clocks | No shared clock. Times are **durations** (seconds), measured by the sender with `computer.uptime()`; the hub timestamps what it receives |

## Envelope

Every message has these fields. Receivers ignore fields they don't know.

| Field | Type | Meaning |
|---|---|---|
| `proto` | `"lens/1"` | Protocol and major version. Receivers drop other majors |
| `kind` | string | `hello`, `describe` or `snapshot` |
| `node` | string | Unique name of the sending computer, from its config (`prism-ore`, `power-main`). The hub's own name for `hello` |
| `role` | string | What the program is: `hub`, `prism`, `power`, ... Also the metric name prefix |
| `boot` | integer | Random number chosen at startup. A new `boot` means the node restarted |
| `seq` | integer | Counts up from 1 for each message the node sends in this boot |
| `version` | string? | Software version of the sender |
| `token` | string? | See *Auth* |

## Messages

| `kind` | From → to | When | Body |
|---|---|---|---|
| `hello` | hub → broadcast | Hub start, and when it sees a snapshot whose `dseq` it has no descriptors for (then sent directly to that node) | none |
| `describe` | agent → broadcast | Agent start, in reply to `hello`, and whenever a metric is added | `dseq`, `metrics` |
| `snapshot` | agent → broadcast | Every `interval` seconds; also early, at most once a second, when health or the set of alerts changes; in reply to `hello` | below |

On `hello`, an agent waits a random 0–2 s (so many agents don't answer at once), then sends `describe` and a
`snapshot`.

### `describe`

| Field | Type | Meaning |
|---|---|---|
| `dseq` | integer | Descriptor version. Increases whenever `metrics` changes during this boot |
| `metrics` | `{ [name] = { type, help, unit? } }` | Every metric the node may send. `type` is `gauge` or `counter`; `help` is one short line; `unit` is display text (`EU/t`, `items`, `mB`, `s`) |

If the descriptors don't fit in one packet, they're split into parts exactly like a snapshot (`sid`, `part`, `parts`).

### `snapshot`

A snapshot is the **complete** current state of the node, not a change. A lost packet costs nothing: the
next snapshot replaces everything.

| Field | Type | Meaning |
|---|---|---|
| `interval` | number | Seconds until the next regular snapshot. The hub uses it to detect silence |
| `health` | `"ok" \| "warn" \| "bad"` | The agent's own verdict |
| `dseq` | integer | The descriptor version these samples follow |
| `samples` | `{ name, value, labels? }[]` | Positional, to save bytes: `{ "prism_backlog_items", 4200, { process = "ore" } }` |
| `alerts` | `{ id, level, text, age? }[]` | Active problems (see *Alerts*) |
| `moreAlerts` | integer? | Alerts left out because part 1 couldn't hold them all. The `bad` ones are kept first |
| `sid` | integer | Snapshot id: the `seq` of its first part |
| `part`, `parts` | integer | Part number (from 1) and the total. `1, 1` when it fits in one packet |

**Splitting.** When the serialized snapshot exceeds 7 KB, the agent splits `samples` across parts. Every
part carries the envelope plus `sid`, `part` and `parts`, and has its own `seq`; only part 1 carries
`interval`, `health`, `dseq` and `alerts`. The hub applies a snapshot only once all its parts have arrived, and discards an incomplete one when
a newer `sid` arrives from that node or after `interval` seconds.

## Metrics

### Types

| Type | Meaning | The hub derives |
|---|---|---|
| `gauge` | A value that goes up and down: stored EU, backlog, a 0/1 flag | Current value, min/max/avg over time |
| `counter` | A total that only rises during a boot: items routed, EU generated | `rate()` per second. A new `boot` resets it, so rates never go negative |

Values are Lua numbers (integers or floats). An agent with no valid reading **omits** the sample rather
than sending `nil`, `NaN` or infinity.

### Names

| Rule | Example |
|---|---|
| Lowercase `[a-z][a-z0-9_]*`, prefixed with the node's `role` | `power_eu_stored` |
| Unit at the end of the name: `_eu`, `_eut` (EU/t), `_items`, `_mb` (fluids, millibuckets), `_seconds` | `power_eu_stored`, `fluids_stored_mb` |
| `_ratio` for fractions 0..1 | `power_fill_ratio` |
| `_total` for counters | `prism_items_routed_total` |
| Flags read as yes/no questions | `power_backup_enabled` |

### Labels

Labels split one metric into series: `prism_backlog_items{process="ore"}`.

| Rule | Why |
|---|---|
| Keys follow the same pattern as names; values are strings | Predictable selectors |
| At most 4 labels per series | Packet size |
| Values come from a small, fixed set: processes, machines, banks, generators. **Never item names** | Each label value is a separate series. PRISM's per-item catalog stays in PRISM's own protocol |
| `node` is reserved | The hub adds it to every series |

### Flags and states

A flag is a gauge that is 0 or 1. A thing with several states uses **one series per state**, each 0 or
1, with exactly one at 1:

```
prism_machine_state{process="ore", machine="mac1", state="running"}  1
prism_machine_state{process="ore", machine="mac1", state="idle"}     0
prism_machine_state{process="ore", machine="mac1", state="down"}     0
```

The hub can then count states with `sum(...)` without knowing what they mean. The agent decides which
state applies, because it has the domain knowledge. For example, `idle` means there's no work, and `down`
means work is waiting but the machine isn't running.

### Series lifetime

A series exists while the node sends it. A series that is missing from a node's latest complete snapshot is
gone; there is no separate delete message.

## Health

| Value | Set by | Meaning |
|---|---|---|
| `ok`, `warn`, `bad` | Agent | Its own verdict, usually the worst of its active alerts |
| `stale` | Hub | No complete snapshot for 3 × `interval`. The computer may be off, crashed, or in an unloaded chunk |

The hub shows `stale` instead of the agent's last health. A base's overall health is the worst health among
its nodes; the hub's config can mark nodes as non-critical.

## Alerts

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Stable for the condition, unique within the node: `stall:ebf`, `down:mac1`, `lsc-low` |
| `level` | `"warn" \| "bad"` | |
| `text` | string | ≤ 80 characters, readable on a HUD line |
| `age` | number? | Seconds since the agent first saw the condition |

An alert is active while it appears in the node's snapshots and cleared when it stops appearing. The hub
dedupes by `node` + `id` and keeps acknowledgements; agents don't track acks.

The hub can also raise its own alerts from rules over metrics from several nodes (for example, low power
while the ore line has a backlog). Those appear alongside agent alerts.

## Compatibility

- Within `lens/1`, changes **add** fields or message kinds and never rename or remove them. Receivers ignore
  anything they don't know.
- A change that breaks this becomes `lens/2`; the hub may accept both for a while.

## Example

PRISM running the ore line, one packet:

```lua
{ proto = "lens/1", kind = "snapshot", node = "prism-ore", role = "prism", boot = 81723, seq = 412,
  version = "0.7.0", interval = 10, health = "warn", dseq = 1, sid = 412, part = 1, parts = 1,
  samples = {
    { "prism_backlog_items", 4200, { process = "ore" } },
    { "prism_machine_state", 1, { process = "ore", machine = "mac1", state = "running" } },
    { "prism_machine_state", 0, { process = "ore", machine = "mac1", state = "idle" } },
    { "prism_machine_state", 0, { process = "ore", machine = "mac1", state = "down" } },
    { "prism_machine_state", 0, { process = "ore", machine = "mac2", state = "running" } },
    { "prism_machine_state", 0, { process = "ore", machine = "mac2", state = "idle" } },
    { "prism_machine_state", 1, { process = "ore", machine = "mac2", state = "down" } },
    { "prism_items_routed_total", 182345 },
  },
  alerts = { { id = "down:mac2", level = "warn", text = "mac2 stopped with work waiting", age = 95 } },
}
```

With its `describe`:

```lua
{ proto = "lens/1", kind = "describe", node = "prism-ore", role = "prism", boot = 81723, seq = 1, dseq = 1,
  sid = 1, part = 1, parts = 1,
  metrics = {
    prism_backlog_items      = { type = "gauge",   help = "Items waiting per process", unit = "items" },
    prism_machine_state      = { type = "gauge",   help = "Machine state (one of running, idle, down)" },
    prism_items_routed_total = { type = "counter", help = "Items moved to outputs", unit = "items" },
  },
}
```
