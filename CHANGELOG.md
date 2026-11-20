# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **The alert log survives restarts**: LOG is kept in `/home/lens-log.cfg` (the last 300 entries, saved once a
  minute and when `lens-hub` stops), with when `lens-hub` started and stopped. Times are real: `3h12m ago`, or
  clock times (`06:40`, `Thu 17:42`) with the new `timezone` setting.
- **Timeline** on LOG: a band per node over the last 12 hours (**24 H** for a day), colored by its worst alert at
  each moment, so you see what happened overnight without reading every row.
- **Panel page**: tap a panel for its history as a chart, low / average / high, the alerts that started
  meanwhile, what each part of its query comes to, which status rule set its dot, and where it's shown; EDIT VIEW
  and ADD TO MY HUD from there.
- **Glance mode** (`glance` in lens-hub.cfg): after a few minutes without a tap the hub draws at a third of its
  resolution, so health, the views you pick and the two worst alerts read from across the room. A tap goes back.
- **Node page**: tap a node for its health, version, how often it reports, its distance, how many snapshots
  arrived whole or cut short, its alerts, its last 24 hours, its metrics and the views that read them. FORGET drops
  a node that stopped.
- **Missing and restarted nodes**: the hub remembers every node it has heard, so after a restart one that
  doesn't report shows as `STALE` ("not heard since hub start") instead of being absent. A node's restarts are on
  LOG, its node page and the timeline, and 3 within an hour raise a warn.
- **Mute** a node (1 h, 4 h or until it clears) or one alert from the node page, while you rebuild a line:
  its alerts stay listed but don't beep, show in HUDs or count towards health. LOG records who muted what.
  Nothing is sent to the agent.
- **Grouped alerts**: a node with 3 or more alerts is one row on the dashboard (`prism-ore: 7 alerts (3 bad)`), so
  one broken line doesn't push the rest off the screen. Tap it for the node page, where each can be acknowledged.
- **Alerts made on the screen**: EDIT > ALERTS, or SAVE AS ALERT on DATA and a panel's page. Type the text, the
  query and how long it must stay true; NOW says whether it's true and when it would fire. Kept in
  `lens-board.cfg`; lens-hub.cfg's rules are listed read-only.
- **Alerts by node in the HUD**: an alerts element can show only some nodes' alerts (`nodes = "^prism"`) or only
  BAD ones (`level = "bad"`); in the HUD editor, NODES and BAD ONLY. Each player sees the lines they look after.
- **New-alert flash** in the HUD: a new BAD alert makes the blocks that list it blink for 10 seconds.
- **Welcome back** in the HUD: after a while with your glasses off, putting them on shows for 20 seconds how
  long you were away, the alerts that started meanwhile and the nodes that restarted. (Whether logging out counts
  as taking them off is still to be checked in game.)
- **Alarm output** (`alarm = { side = "north" }`): a redstone card in the hub computer gives a signal while a BAD
  alert is neither acknowledged nor muted, for a lamp or a siren. Not tried in game yet: `lens-discover --redstone
  north` is the check.
- **Alerts in chat** (`chat = true`): each new BAD alert also goes to the chat of the players wearing glasses
  whose HUD would list it. Not tried in game yet: `lens-discover --chat <name>` is the check.
- **Who acknowledged an alert**: `✓ Aaron` on the dashboard, and on LOG after the alert ends.

## [0.5.1] - 2026-11-18

### Fixed
- **`dots = "left"` on a HUD block in `lens-hub.cfg`** is kept: it was dropped, so the dots stayed on the
  right until the block was changed in the HUD editor.

## [0.5.0] - 2026-11-18

### Added
- **Dots on the left**: a HUD block's `dots = "left"` (Dots RIGHT / LEFT in the HUD editor) puts state dots
  before the label.
- **REFRESH** in the HUD editor: wipes the glasses and draws the HUDs again, settings unchanged, for a HUD
  that's stuck or doubled.

### Fixed
- **HUD dots no longer jump** when a view's value has no data: the label stays whole, the dot stays put and a
  dim `–` takes the value's place.
- **No frozen second HUD after a restart**: `lens-hub` removes every widget on its terminals at start, so one
  left by a crash or a computer switched off goes away.

## [0.4.0] - 2026-11-13

### Added
- **The SPECTRA logo** in pixel art for a moment while `lens-hub` starts, with LENS's name and version.

### Changed
- **Colors** follow the SPECTRA logo: LENS blue (`#5EB4FF`) as the accent on the dashboard, and in the HUD
  for bars and OK; the logo's ink, background and green, yellow and red for status.

## [0.3.0] - 2026-11-12

Status you define, pages, presets, a log, and editing that's comfortable on the screen. Works with PRISM 1.2.0
and LUMEN; agents need no update (lens/1 is unchanged). `lens-board.cfg` converts itself on first start.

### Added
- **Status dots** (`status`): rules in order, `{ level, query }`; the first true one colors the dot (none:
  gray). `$value` is the view's value; `color = "status"` colors the value too. Levels: good, warn, bad, off.
- **A dot per item** (`dots`, `by`, `states`): one per machine (or any label), colored by your map of state
  to level (a default covers running, idle, down and the like).
- **Several values in one line** (`text`, `values`): `"{stored} / {cap} EU"`, each value formatted.
- **`when`**: a panel or HUD line shows only while its query is true.
- **View editor:** fields for all of the above, with the preview showing dots and the filled-in text. Status
  rules and dot states are rows: a color chip to tap, a query or name, ▲ ▼ ✕.
- **A cursor in every text field:** tap to place it, ← → Home End to move it, Backspace and Delete, typing and
  pasting at the cursor; ↑ ↓ move between fields; long fields scroll to keep it in view.
- **Dashboard pages:** up to 8 named pages of panels, with tabs under the header; made, renamed and deleted on
  the EDIT page.
- **Alert log** (LOG): alerts happening now, and the last 100 that ended, with when and how long they lasted.
- **HUD presets:** up to 8 named HUDs per player, switched, copied, renamed and deleted in the HUD editor.
- **docs/views.md**, **docs/hud.md** and **docs/examples.md** (ready-made views and HUD layouts for PRISM and
  LUMEN; the tests load every example and check what it shows).

### Changed
- **lens-setup** writes the HUD as blocks: a line per PRISM router (its backlog, with a status dot: red when a
  machine is down, green while one runs) instead of a bar. An old one-corner `hud` is rewritten as a block
  with the same content.
- `lens-board.cfg` converts itself on first start: 0.2.0's panels become the page `Main`, each player's HUD
  becomes the preset `main`.
- Inside: one page module per screen (`hub/pages/`), one editor module per editor (`hub/editors/`), shared
  drawing in `hub/frame`; `tests/test_layout.lua` checks dependencies point one way. The DATA page no longer
  fills the hub's query cache.

### Removed
- Reading `lens-hud.cfg` (the 0.2.0 pre-release file, already moved into `lens-board.cfg` by 0.2.0).

### Fixed
- The HUD editor drew neither its position controls nor its footer when a block's list ran past the bottom of
  the screen.
- With no panels, the dashboard said "No panels in lens-hub.cfg." It now says to tap EDIT.

## [0.2.0] - 2026-11-12

The dashboard and HUD, set up on the screen. Works with PRISM 1.2.0 and LUMEN; agents need no update (the
lens/1 protocol is unchanged).

### Added
- **DATA page:** every metric every agent sends, its series with labels and values; tap label values and a
  function to build a query, see its value, then **SAVE AS PANEL** or **ADD TO MY HUD**.
- **EDIT on the dashboard:** order, add and remove panels; a **library of views** (lens-hub.cfg's, changed or
  new ones) made and changed on the screen, typed with a keyboard, the value previewed as you type; UNDO.
  Saved in `/home/lens-board.cfg` (only the hub writes it), with players' HUDs (an earlier `lens-hud.cfg` is
  read in once). `editors` limits who may edit. One editor at a time, for the player who opened it.
- **HUD blocks:** a HUD is one or more blocks, each hung from one of nine anchor points (corners, edge
  middles, center) and nudged from it, so it can sit clear of a minimap or other overlay.
- **HUD elements:** `bar`, `text` (label and value on one line), `alerts` and `gap`. The old `hud` form (one
  corner, `bars`, `alerts`) still works as one block.
- **`format`** for panels and HUD elements: `auto`, `percent`, `duration` (`2h 05m`), `signed` (`+2.4k`).
  **`color`**: `thresholds`, `sign` (green above zero, red below) or `none`.
- **`resolution = "fit"`** (the default): the dashboard matches the screen's shape in blocks, so a 3 × 4 screen
  is filled (73 × 50). Tall screens keep sparklines.
- **A HUD for each player**: the hub drives every Glasses Terminal attached to it, each showing the HUD of the
  player wearing glasses linked to it, placed for their view size. One terminal per player.
- **HUD editor** on the dashboard (tap **HUD**): your blocks (add, remove), their elements (add any panel or
  default HUD view, bar or text, order, alerts, gaps), anchor grid, nudges (1, 8 or 32 px), width and size.
  Only the player who tapped can change their HUD; changes apply at once and are saved in `lens-board.cfg`.
- **`editors`** in lens-hub.cfg: who may change the dashboard on the screen (nil: anyone).

### Changed
- The header has DATA, EDIT and HUD buttons; on narrow screens its summary shortens and the hub's name and
  port make way.
- Panels come from `lens-board.cfg` once it exists: lens-hub.cfg's panels are its starting point, and a panel
  added there later (by lens-setup) is added to the dashboard once.

## [0.1.0] - 2026-11-12

The first release. Works with PRISM 1.2.0, which reports to LENS.

### Added
- **`lens-hub`**, the hub and its dashboard: overall health, each agent and when it last reported, one list
  of every alert (tap to acknowledge, ACK ALL), and configured panels with bars and sparklines. Tier 2 and
  tier 3 screens. Agents that stop reporting raise a `stale` alert; new `BAD` alerts beep.
- **AR glasses HUD** on an OC Glasses Glasses Terminal attached to the hub: chosen bars and the newest
  unacknowledged alerts, with a health strip, in a corner of the view (`hud` in lens-hub.cfg). Only changed
  values are sent; the dashboard shows the HUD's calls per minute and any HUD error.
- **`lens-setup`**: guided setup that finds the agents on the network, offers each PRISM router's panels and
  HUD bar, and can start the hub on boot. Keeps your edits and a `.bak`.
- **Queries and rules** (docs/queries.md): selectors with label matchers, `sum`/`count`/`max`/`min`/`avg`/
  `rate`, arithmetic and comparisons, for panels, bars and the hub's own alerts (`for` seconds).
- **`lens-discover`**: lists a computer's components with every method and its docs (`--widgets`,
  `--events`, `--glasses-test` for glasses), to build against a mod's real API.
- **`lens-update`**: installs and updates LENS from GitHub (releases, a branch, a tag or a fork).
- **The `lens/1` protocol** (docs/telemetry.md) and the `lens.metrics` / `lens.codec` modules agents report
  with: health, gauges and counters with labels, alerts; snapshots split into packets that fit the network.
