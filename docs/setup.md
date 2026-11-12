# Setup

## The hub computer

| Part | Why |
|---|---|
| Computer case, CPU, RAM (tier 2+), hard drive with OpenOS | Lua 5.3 architecture (shift-right-click the CPU in hand to switch) |
| **GPU and screen**, tier 3 | The full dashboard (160x50). Tier 2 (80x25) works with a stacked layout |
| Keyboard | For `lens-setup` |
| **Network card** that reaches the agents | Wireless (range permitting, or through relays), wired, or a **linked card** for an agent in another dimension. The protocol is the same on every one |
| Internet Card | For `lens-update` (optional: copy the files by hand instead) |
| **Glasses Terminal** (OC Glasses), optional | The AR glasses HUD. Place it next to the computer (or connect it with cable) and link your glasses to it |

LENS only listens and draws: the hub doesn't need adapters, a database or anything on your networks.

## Install

On the hub computer, with an Internet Card:

```
wget -f https://raw.githubusercontent.com/aharabedian/lens/main/src/lens-update.lua /home/lens-update.lua
/home/lens-update
```

This installs `lens-hub`, `lens-setup`, `lens-discover` and `lens-update` on the shell path, and
`/home/lens-hub.example.cfg`. It installs the latest release (or `main` while there are none).

## Connecting agents

Agents report to the hub on its port (4243 by default) with its secret, apart from anything else on the
network. For each **PRISM** router (PRISM's `main` branch until its next release: `prism-update main`):

1. Run `prism-setup` on the router. Its "LENS monitoring" step (or the LENS row on the editor's GENERAL tab)
   asks for the LENS port, a name for this router (`prism-ore`, `prism-smelt`...) and the secret.
2. Restart `prism`. It reports after every scan.

Details: PRISM's `docs/configuration.md`, "Reporting to LENS".

## First run

1. Start the agents (above), so the hub can find them.
2. On the hub, run **`lens-setup`**:

   | Step | Asks |
   |---|---|
   | 1. Hub | Its name, port and secret |
   | 2. Agents and panels | Says hello on the port and lists the agents that answer; for each PRISM router, offers its panels: backlog, machines running, machines down |
   | 3. AR glasses HUD | With a Glasses Terminal attached: show a HUD, which corner, and a bar for each router (machines running, or backlog against a size you pick) |
   | 4. Start on boot | Adds `lens-hub` to `/home/.shrc` (other lines are kept) |

   It shows the file before saving `/home/lens-hub.cfg` (the old one is kept as `lens-hub.cfg.bak`).
3. Run **`lens-hub`** (or reboot, with start on boot).

Run `lens-setup` again whenever you add an agent: your settings are the defaults, panels and bars you have
are kept, and only new agents are offered. Anything else (rules, thresholds, `nonCritical`) is edited in
`/home/lens-hub.cfg`: [hub.md](hub.md) has every option. Hand edits survive a `lens-setup` run; comments don't.

`lens-hub` also runs with no config at all: it finds agents and lists their alerts, with no panels.

## Updating

```
lens-update                   the latest release (the default)
lens-update main              follow the main branch (newest, may be unfinished)
lens-update v0.1.0            a release, and stay on it
lens-update OWNER/REPO [REF]  a fork
```

The choice is saved for next time. Your `lens-hub.cfg` is never touched. GitHub can serve a file's old
version for a few minutes after a change: if an update seems to change nothing, wait and run it again.
Restart `lens-hub` after updating.
