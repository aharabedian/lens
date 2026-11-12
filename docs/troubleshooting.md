# Troubleshooting

The hub's screen is the first place to look: the footer shows HUD errors, and each node shows when it last
reported. `lens-discover` shows what the hub computer can see.

## The hub

| Symptom | Fix |
|---|---|
| `LENS's modules are missing ... run lens-update` | Run `lens-update` |
| `lens-hub needs a network card` | Add a wireless or wired network card (or a linked card) |
| `/home/lens-hub.cfg: panel 2 (Ore): value: expected ) at 14` | A mistake in that panel's query (or rule, or HUD bar); [queries.md](queries.md) has the syntax |
| "Waiting for agents" and nothing appears | The agent isn't reporting on this port: check its `lensPort` matches the hub's `port`, and `lensToken` its `token` (both or neither). Check range (wireless) and that the agent runs |
| `lens-setup`: "no agents answered" | Same as above; start the agents first |
| A node shows **STALE** | No snapshot for `staleAfter` intervals: the agent stopped, crashed, or its chunk unloaded (keep agents chunk-loaded), or it's out of wireless range |
| A panel shows `–` | Its query found no data: a typo in a metric or label, or the node is stale. Selectors are case-sensitive |
| A panel counts machines wrong | `count(...)` counts series, not values: to count machines in a state, `sum` their state series ([queries.md](queries.md)) |
| An update changed nothing | GitHub served the old files for a few minutes; wait and run `lens-update` again, then restart `lens-hub` |
| The hub beeps too much | `beep = false`, or acknowledge the alerts (only new `BAD` alerts beep) |

## AR glasses HUD

| Symptom | Fix |
|---|---|
| No HUD | The Glasses Terminal must be attached to the hub computer (`lens-discover` lists `glasses`), your glasses linked to it and worn, and `hud` not `false` |
| `HUD: <error>` in the dashboard's footer | The terminal failed (for example its chunk unloaded). The dashboard keeps running; restart `lens-hub` once it's back |
| The HUD is off screen or in the wrong place | It places itself from your view's size when you put the glasses on: take them off and on again. Or pick another `hud.anchor` |
| Only "LENS OK" and alerts, no bars | Add `hud.bars` (`lens-setup` offers one per PRISM router) |
| A bar has no fill | Bars need `max`, `of` or `percent` |
| Text is cut off with … | Widen `hud.width` (about 5 GUI pixels per character at scale 1) |
| Colors are black or white blocks | Another glasses mod taking 0..255 colors: `hud.colors = "byte"` |

The dashboard's footer shows how many calls the HUD made in the last minute: about 0 when nothing changes.
