# LENS

**Live Engineering & Network Status**: base-wide monitoring for GregTech: New Horizons, on OpenComputers.

[PRISM](https://github.com/aharabedian/prism) splits one stream of items into many machines. LENS does the
opposite: it gathers status from every system in the base into one place.

- **Agents** (PRISM, a power monitor, ...) push **health**, **metrics** and **alerts** over wireless in a
  shared, Prometheus-inspired format. Agents keep working when the hub is down.
- **The hub** collects them, notices nodes that went quiet, merges alerts, keeps short history and computes
  base-wide figures (net EU/t, total backlog, machines down).
- **Displays**: a dashboard screen and an AR glasses HUD, both built from the hub's config.

![The hub](docs/images/dashboard.png)

> Status: early. The hub and PRISM's reporting work in tests; not yet tried in game.

**Install the hub:** [docs/hub.md](docs/hub.md). **Write queries:** [docs/queries.md](docs/queries.md).
**Write an agent:** [docs/telemetry.md](docs/telemetry.md) and [docs/architecture.md](docs/architecture.md).

## Roadmap

1. ✓ Telemetry spec ([docs/telemetry.md](docs/telemetry.md)): envelope, message types, metric types and naming, health, alerts.
2. ✓ Shared `metrics` and `codec` modules, used by every agent.
3. ✓ A simulated wireless network in the test mock, so hub and agents run together in tests.
4. ✓ Hub core: storing snapshots, staleness, the selector language, alerts.
5. PRISM exports its backlog and machine states. **First milestone: the hub shows them on a screen.**
   Built and tested (PRISM's `lens-telemetry` branch, `lens-hub`); next: try it in game.
6. AR glasses HUD.
7. Power agent.
8. History graphs.

LENS observes; it doesn't control. Each system's own UI (like PRISM's control screen) is where control lives.

## Development

```
make dev      # install luacheck and a Python venv for screen rendering (once)
make check    # lint + tests
make screens  # render the screens the tests draw into build/screens/*.png
```

See [CONTRIBUTING.md](CONTRIBUTING.md).
