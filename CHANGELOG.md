# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **A HUD for each player**: the hub drives every Glasses Terminal attached to it, each showing the HUD of the
  player wearing glasses linked to it, placed for their view size. One terminal per player.
- **HUD editor** on the dashboard (tap **HUD**): pick and order your bars from `hud.bars` and the panels,
  corner, size, width and alerts. Only the player who tapped can change their HUD; changes apply at once and
  are saved in `/home/lens-hud.cfg`.

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
