# The hub

`lens-hub` listens for every agent in the base and shows them on one screen: overall health, each node,
every alert, and the panels you configure. It only watches; control stays in each system's own UI.

![The hub on a tier 3 screen](images/dashboard.png)

## Install

The hub computer needs a **GPU and screen** (tier 3 for the full layout; tier 2 works) and a **network card**
that reaches the agents (wireless, wired, or a linked card for another dimension). Installing needs an
**Internet Card**.

```
wget -f https://raw.githubusercontent.com/aharabedian/lens/main/src/lens-update.lua /home/lens-update.lua
/home/lens-update
lens-hub
```

`lens-update` installs the latest release, or `main` while there are no releases (`lens-update main` to
follow it). The hub runs with no config: it finds agents and lists their alerts. For panels and rules, copy
`/home/lens-hub.example.cfg` to `/home/lens-hub.cfg` and edit it.

## Connecting PRISM

On each PRISM router, set in `prism.cfg` (PRISM's docs: "Reporting to LENS"):

```lua
lensPort  = 4243,         -- the hub's port
lensNode  = "prism-ore",  -- a name per router; panels select it with node="prism-ore"
lensToken = nil,          -- the hub's token, if it has one
```

Restart `prism`. The hub lists the router within one scan.

## The screen

| Part | Shows |
|---|---|
| Header | Overall health (the worst of the critical nodes), node count, alert counts, the hub's name and port, QUIT |
| NODES | Each agent: health (`STALE` when it stopped reporting), role, when it last reported |
| ALERTS | Every active alert, `BAD` first, then oldest. **Tap one to acknowledge it**; ACK ALL acknowledges every alert. An acknowledged alert stays listed (✓, dimmed) until it clears, and comes back unacknowledged if it gets worse |
| PANELS | Your panels: label, value, a bar for `max` / `of` / `percent`, and a sparkline of its history (tier 3) |

On a screen narrower than 120 columns, panels, nodes and alerts stack. The hub beeps when a new `BAD`
alert appears. It redraws only what changed (about 2 GPU calls a second when nothing happens).

![The hub on a tier 2 screen](images/dashboard-tier2.png)

## `lens-hub.cfg`

Every key is optional. Start from `lens-hub.example.cfg`.

| Key | Default | Meaning |
|---|---|---|
| `node` | `"hub"` | This hub's name. Its rule alerts are listed under it |
| `port` | `4243` | The LENS port: every agent's `lensPort`. Keep it apart from PRISM's control port |
| `token` | `nil` | Shared secret: every agent sends the same (PRISM: `lensToken`). Messages without it are ignored |
| `staleAfter` | `3` | Missed snapshots before a node counts as stopped reporting (a `BAD` alert) |
| `beep` | `true` | Beep when a new `BAD` alert appears |
| `sample` | `10` | Seconds between sparkline samples |
| `nonCritical` | `{}` | Node names whose silence is only a warning and that don't count towards overall health |
| `panels` | `{}` | See below |
| `rules` | `{}` | The hub's own alerts, see below |

A mistake in the file stops `lens-hub` with the panel or rule named: `panel 2 (Ore): value: expected ) at 14`.

### Panels

```lua
{ label = "Ore backlog", value = 'sum(prism_backlog_items{node="prism-ore"})', max = 10000, unit = "items",
  warnAbove = 5000, badAbove = 9000 },
```

| Key | Meaning |
|---|---|
| `label` | Name shown on the panel (required) |
| `value` | A [query](queries.md) (required) |
| `max` | Draw a bar of `value / max` |
| `of` | A query: show `value/of` and a bar of the fraction. Use `count(...)` of a state series for "how many machines" |
| `percent` | `true` when `value` is 0..1: show it as a percentage, with a bar |
| `unit` | Text after the value |
| `warnAbove`, `badAbove`, `warnBelow`, `badBelow` | Color the value and bar yellow or red past these |

Values show as `4.2k`, `1.5M`, `3G`. A query with no data shows `–`.

### Rules

```lua
{ id = "ore-backlog", level = "warn", text = "Ore backlog over 9k for 5 minutes",
  when = 'sum(prism_backlog_items{node="prism-ore"}) > 9000', ["for"] = 300 },
```

`when` is a query that is true when non-zero; the alert fires once it has been true for `for` seconds
(default 0). Missing data is false, so a node going quiet raises its stale alert instead.
