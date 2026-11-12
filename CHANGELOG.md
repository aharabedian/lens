# Changelog

## Unreleased

- Repository scaffold: test runner, lint, CI.
- Telemetry protocol `lens/1` specified (docs/telemetry.md).
- `lens.metrics` and `lens.codec`: the registry every agent fills, and lens/1 messages split into packets and joined back.
- Hub core (`lens.hub.*`): nodes and their series, counter rates, stale nodes, the query language
  (docs/queries.md), alert rules, and one alert list with acknowledgements.
