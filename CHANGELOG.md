# Changelog

## Unreleased

- Repository scaffold: test runner, lint, CI.
- Telemetry protocol `lens/1` specified (docs/telemetry.md).
- `lens.metrics` and `lens.codec`: the registry every agent fills, and lens/1 messages split into packets and joined back.
- Hub core (`lens.hub.*`): nodes and their series, counter rates, stale nodes, the query language
  (docs/queries.md), alert rules, and one alert list with acknowledgements.
- **`lens-hub`**: the hub program and its dashboard: overall health, nodes, alerts (tap to acknowledge),
  and panels with bars and sparklines from `/home/lens-hub.cfg` (optional; docs/hub.md). Tier 2 and 3 screens.
- **`lens-update`**: installs and updates LENS from GitHub.
- **AR glasses HUD**: with an OC Glasses Glasses Terminal on the hub computer, `lens-hub` draws health, panel
  bars and the newest unacknowledged alerts in the glasses (`hud` in lens-hub.cfg; docs/hub.md).
- **`lens-discover [type] [--all]`**: lists the computer's components with every method and its docs, into
  `/home/lens-discover.txt`, to build agents and the HUD against a mod's real API. `--widgets` lists what
  the Glasses Terminal's widget objects offer; `--events N` prints every event for N seconds; `--glasses-test` draws a calibration pattern.
