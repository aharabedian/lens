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
| The HUD is off screen or in the wrong place | It places itself from your view's size when you put the glasses on: take them off and on again. Or move it: tap **HUD** on the dashboard |
| Only "LENS OK" and alerts, no bars | Add some: tap **HUD** on the dashboard (any panel or view), or `hud` in lens-hub.cfg (`lens-setup` offers one per PRISM router) |
| A bar has no fill | Bars need `max`, `of` or `percent` |
| Text is cut off with … | Widen the block (**Width** in the HUD editor, or `width`; about 5 GUI pixels per character at scale 1) |
| Colors are black or white blocks | Another glasses mod taking 0..255 colors: `hud.colors = "byte"` |
| Everyone sees the same HUD | A terminal shows one HUD to everyone linked to it: link each player's glasses to a terminal of their own ([hub.md](hub.md#a-hud-for-each-player)) |
| My HUD sits under the minimap or another overlay | Tap **HUD** on the dashboard, pick an anchor, nudge it clear (watch the glasses while you tap) |

The dashboard's footer shows how many calls the HUD made in the last minute: about 0 when nothing changes.

## Editing on the screen

| Symptom | Fix |
|---|---|
| Typing in the view editor does nothing | Attach a keyboard to the hub's screen (the editor says when there's none). Only the player who opened the editor can type |
| Footer: "Steve is editing (free in 40s)" | One editor at a time: wait, or ask them to tap DONE |
| "Only Steve can edit the dashboard." | `editors` in lens-hub.cfg lists who may; anyone can still change their own HUD |
| SAVE says what's wrong ("value: expected ) at 14") | The query, as typed: the **Now** line shows the error as you type. [queries.md](queries.md) has the syntax |
| A panel I added to lens-hub.cfg doesn't show | It's added to the dashboard once, unless it was taken off on the screen: tap EDIT, find it in the library, **+** |
| A panel I added went missing | It may be on another page: the tabs under the header (or EDIT's PAGES row) show them all |
| The LOG is empty after a restart | It's kept in memory only: it starts over when `lens-hub` starts |
| I want to start the screen setup over | Delete `/home/lens-board.cfg` and restart `lens-hub`: lens-hub.cfg's panels and HUD come back |
