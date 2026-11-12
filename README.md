# LENS

**Live Engineering & Network Status**: base-wide monitoring for GregTech: New Horizons, on OpenComputers.

[PRISM](https://github.com/aharabedian/prism) splits one stream of items into many machines. LENS does the
opposite: it gathers status from every system in the base into one place.

- **Agents** (PRISM, a power monitor, ...) push **health**, **metrics** and **alerts** over wireless in a
  shared, Prometheus-inspired format. Agents keep working when the hub is down.
- **The hub** collects them, notices nodes that went quiet, merges alerts, keeps short history and computes
  base-wide figures (net EU/t, total backlog, machines down).
- **Displays**: a dashboard screen and an AR glasses HUD, both built from the hub's config.

> Status: early. The telemetry format is being specified first; see the roadmap below.

## Roadmap

1. Telemetry spec ([docs/telemetry.md](docs/telemetry.md)): envelope, message types, metric types and naming, health, alerts.
2. Shared `metrics` and `codec` modules, used by every agent.
3. A simulated wireless network in the test mock, so hub and agents run together in tests.
4. Hub core: storing snapshots, staleness, the selector language, alerts.
5. PRISM exports its backlog and machine states. **First milestone: the hub shows them on a screen.**
6. AR glasses HUD.
7. Power agent.
8. History graphs, sending commands through the hub.

## Development

```
make dev      # install luacheck into .luarocks/ (once)
make check    # lint + tests
```

See [CONTRIBUTING.md](CONTRIBUTING.md).
