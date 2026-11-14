# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
