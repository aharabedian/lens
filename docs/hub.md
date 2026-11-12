# The hub

`lens-hub` listens for every agent in the base and shows them on one screen: overall health, each node,
every alert, and the panels you configure. It only watches; control stays in each system's own UI.

![The hub on a tier 3 screen](images/dashboard.png)

Install, connecting agents and the first run: [setup.md](setup.md). Problems: [troubleshooting.md](troubleshooting.md).

## The screen

| Part | Shows |
|---|---|
| Header | Overall health (the worst of the critical nodes), node count, alert counts, the hub's name, port and version, **LOG** ([below](#the-alert-log)), **DATA** ([below](#the-data-page)), **EDIT** ([editing on the screen](#editing-on-the-screen)), **HUD** (with a Glasses Terminal), QUIT |
| NODES | Each agent: health (`STALE` when it stopped reporting), role, when it last reported |
| ALERTS | Every active alert, `BAD` first, then oldest. **Tap one to acknowledge it**; ACK ALL acknowledges every alert. An acknowledged alert stays listed (✓, dimmed) until it clears, and comes back unacknowledged if it gets worse |
| Page tabs | With more than one page: tap one to show its panels (anyone may) |
| PANELS | The shown page's panels: label, value, a bar, status and state dots ([views.md](views.md)), and a sparkline of its history (tier 3) |

On a screen narrower than 120 columns, panels, nodes and alerts stack; on a tall one (40 rows or more)
panels keep their sparklines. The hub beeps when a new `BAD` alert appears. It redraws only what changed
(about 2 GPU calls a second when nothing happens).

**Screen shape:** by default (`resolution = "fit"`) the hub picks the resolution that matches the screen's
shape in blocks, so text fills it with no empty borders. Characters are twice as tall as they are wide, so a
3 wide, 4 tall screen gets 73 × 50:

![A 3 x 4 screen](images/dashboard-portrait.png)

![The hub on a tier 2 screen](images/dashboard-tier2.png)

## `lens-hub.cfg`

`lens-setup` writes it (and keeps your edits when you run it again); every key is optional.
`lens-hub.example.cfg` is an annotated example.

| Key | Default | Meaning |
|---|---|---|
| `node` | `"hub"` | This hub's name. Its rule alerts are listed under it |
| `port` | `4243` | The LENS port: every agent's `lensPort`. Keep it apart from PRISM's control port |
| `token` | `nil` | Shared secret: every agent sends the same (PRISM: `lensToken`). Messages without it are ignored |
| `staleAfter` | `3` | Missed snapshots before a node counts as stopped reporting (a `BAD` alert) |
| `beep` | `true` | Beep when a new `BAD` alert appears |
| `sample` | `10` | Seconds between sparkline samples |
| `editors` | `nil` | Player names who may use EDIT: `{ "Steve", "Alex" }`. `nil`: anyone |
| `resolution` | `"fit"` | `"fit"`: match the screen's shape (see above). `"max"`: the GPU's largest. `{ width, height }`: your own, e.g. `{ 80, 25 }` for bigger text |
| `nonCritical` | `{}` | Node names whose silence is only a warning and that don't count towards overall health |
| `panels` | `{}` | The views the dashboard starts with, [below](#panels) |
| `hud` | `{}` | Everyone's default HUD ([hud.md](hud.md)); `false` turns the HUD off |
| `rules` | `{}` | The hub's own alerts, [below](#rules) |

A mistake in the file stops `lens-hub` with the panel or rule named: `panel 2 (Ore): value: expected ) at 14`.

### Panels

Panels are **views**: a label, a query and how it reads ([views.md](views.md) has every key: formats, colors,
bars, status dots, a dot per item, several values in one line, `when`).

```lua
panels = {
  { label = "Ore backlog", value = 'sum(prism_backlog_items{node="prism-ore"})', max = 10000, unit = "items",
    warnAbove = 5000, badAbove = 9000 },
  { label = "Ore line", dots = 'prism_machine_state{node="prism-ore"}' },
},
```

These are the starting point: the dashboard's pages and panels are then changed on the screen (EDIT, below).

### Rules

```lua
{ id = "ore-backlog", level = "warn", text = "Ore backlog over 9k for 5 minutes",
  when = 'sum(prism_backlog_items{node="prism-ore"}) > 9000', ["for"] = 300 },
```

`when` is a query that is true when non-zero; the alert fires once it has been true for `for` seconds
(default 0). Missing data is false, so a node going quiet raises its stale alert instead.

## The alert log

Tap **LOG** for what happened while you were away: alerts happening **now** (and for how long), then the ones
that have **ended**, newest first, with when and how long they lasted (the worst level each reached). The hub
keeps the last 100 that ended, in memory: a restart starts the log over.

![The alert log](images/log.png)

## The DATA page

Tap **DATA** to see everything the agents send and build a query without writing one:

![The DATA page](images/data.png)

1. **Pick a metric** from the list: every metric from every agent that's reporting, with how many series it has
   (`ctr` marks a counter). Long lists page with ◀ ▶.
2. Its unit, help and **every series** with its labels and value (counters also show their rate) appear.
3. **Tap label values** to narrow it down (`any` clears one); the other labels only offer values that still
   match. **Tap a function** (`sum`, `max`, `min`, `avg`, `count`, `rate`) to combine the series. Counters start
   on `rate`.
4. The **query** and its **value** follow every tap.
5. **SAVE AS PANEL** opens it in the view editor (query, a label and the unit filled in) and puts it on the
   dashboard when saved. **ADD TO MY HUD** does the same for your own HUD (a text line in your first block).
   After saving you're back on the DATA page as you left it.

SAVE AS PANEL follows `editors`; anyone can add to their own HUD. On a narrow screen the list and a metric take
turns (◀ METRICS goes back). The [query language](queries.md) is still there for anything the taps can't build:
edit the query in the view editor.

## Editing on the screen

Tap **EDIT** to change the dashboard and the **library** of views. Everything you change here is saved in
**`/home/lens-board.cfg`** (next to lens-hub.cfg), which only the hub writes; lens-hub.cfg is never touched.

![The EDIT page](images/dash-editor.png)

| | |
|---|---|
| PAGES | The dashboard's pages (up to 8): tap one to edit it; **+ PAGE** adds one and asks for its name; **RENAME** (typed); **DELETE PAGE** (not the last; its panels leave the dashboard, the views stay in the library) |
| ON *page* | That page's panels with their values: **EDIT** opens the view ([views.md](views.md#the-view-editor)), ▲ ▼ order, ✕ takes it off (it stays in the library) |
| LIBRARY | Views not on that page: **+** puts one on, **EDIT** opens it, **+ NEW** makes one (on that page). `cfg` marks a view from lens-hub.cfg; `cfg*` one changed here |
| UNDO | Takes back the last change to views or panels (up to 20) |

**EDIT** on a panel or library view, and **+ NEW**, open the **view editor** ([views.md](views.md#the-view-editor)):
its fields, status rules and dot states, with the value previewed as you type. Typing needs a keyboard attached
to the hub's screen.

- Views from lens-hub.cfg can be changed here (your version is kept in lens-board.cfg; **BACK TO lens-hub.cfg**
  drops it) but keep their label and can't be deleted.
- Renaming a view moves the dashboard and players' HUDs along with it.
- A panel later added to lens-hub.cfg (by lens-setup, say) appears on the first page once; one you took off
  stays off.
- One editor is open at a time, for the player who opened it; only their taps and keys count, and it closes
  after a minute without one. `editors` in lens-hub.cfg limits who may open EDIT.

## AR glasses HUD

With Glasses Terminals attached, the hub also draws a HUD in each player's glasses, changed by each player on the
dashboard (tap **HUD**): [hud.md](hud.md).
