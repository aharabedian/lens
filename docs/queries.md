# Queries

The hub picks what it shows and alerts on with small queries over every node's metrics. The dashboard's
**DATA** page builds the common ones by tapping ([hub.md](hub.md#the-data-page)). They're loosely
modelled on PromQL, but much smaller. The grammar is in `lib/lens/hub/query.lua`.

```
sum(prism_machine_state{process="ore", state="running"})       machines running on the ore line
count(prism_machine_state{process="ore", state="running"})     machines on the ore line (one series each)
power_eu_stored / power_eu_capacity                            fill, 0..1
rate(power_eu_generated_total)                                 EU per second, all generators
power_fill_ratio < 0.2 and sum(prism_backlog_items) > 0        a rule: 1 when true, else 0
```

| Part | Meaning |
|---|---|
| `name{label="v", ...}` | The series of a metric whose labels match. Operators: `=`, `!=`, `=~` and `!~` (Lua patterns, unanchored: use `^` and `$`). A missing label matches as `""` |
| `node` label | Every series has one, added by the hub: `node="prism-ore"` |
| A selector on its own | The **sum** of its series |
| `sum`, `max`, `min`, `avg` | Over the matching series; nothing when no series match |
| `count` | **How many series** match, whatever their values. To count machines in a state, `sum` their 0/1 state series |
| `rate` | Summed per-second rates of matching counters |
| `+ - * /` | Arithmetic. Dividing by zero gives nothing |
| `< <= > >= == !=` | 1 or 0 |
| `and`, `or`, `not` | 1 or 0 |

**Nothing** (no data) spreads: `nothing + 1` is nothing, and a comparison with nothing is nothing. In
`and`/`or`/`not` and in rules, nothing counts as false, so a rule never fires because a node went quiet.
Series of stale nodes aren't included; the hub's `stale` alert covers them.
