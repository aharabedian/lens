--[[ lens.hub.pages.node: the node page (lens.hub.editors.node): one agent up close. Health, role, version and boot;
  how often it reports, when it last did, its distance and how many snapshots came whole; its alerts; its last 24
  hours as a band (colored by its worst alert, │ where it restarted); its metrics (as many as fit); and the views
  that read them. FORGET for a node that stopped. MUTE 1 H / 4 H / UNTIL IT CLEARS (or UNMUTE) for the node, and
  MUTE / UNMUTE on each alert (until it clears). Tapping an alert acknowledges it (actions.ack), as on the dashboard.

  node.draw(f, e, actions)   e: the editor's model (its header comment), plus player, error, closesIn
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local node = {}

local C = frame.C
local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad, stale = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD", stale = "STALE" }
local BAND = 15

function node.draw(f, e, actions)
  local buttons = { { "DONE", actions.nodeDone } }
  if e.found and e.stale and e.canForget then table.insert(buttons, 1, { "FORGET", actions.nodeForget, C.line }) end
  f:editorHeader("Node: " .. tostring(e.name), buttons)
  local width, last = f.w - 2, f.h - 2
  if not e.found then
    f:text(2, 3, Gui.fit("The hub doesn't know this node (any more).", width), C.dim)
    f:editorFooter(e, "can use this")
    return
  end
  local y = 3
  local hc = HEALTH_COLOR[e.health] or C.dim
  f:text(2, y, "●", hc)
  f:text(4, y, HEALTH_TEXT[e.health] or "?", hc)
  local about = (e.role or "?") .. (e.version and (" · version " .. tostring(e.version)) or "")
    .. " · boot " .. tostring(e.boot or "?")
  f:text(11, y, Gui.fit(about, f.w - 11), C.dim)
  y = y + 1
  local seen = e.ago and (frame.ago(e.ago) .. " ago") or "never"
  local line = ("reports every %s, last %s"):format(frame.ago(e.interval or 0), seen)
  local t = e.traffic
  if t and t.distance and t.distance > 0 then line = line .. (" · %d m away"):format(math.floor(t.distance + 0.5)) end
  f:text(2, y, Gui.fit(line, width), e.stale and C.bad or C.text)
  y = y + 1
  if t then
    f:text(2, y, Gui.fit(("snapshots since the hub started: %d whole, %d cut short"):format(t.whole, t.cut), width),
      t.cut > 0 and C.warn or C.dim)
    y = y + 1
  end
  if (e.restarts or 0) > 0 then
    f:text(2, y, Gui.fit(("restarts since the hub started: %d, the last %s"):format(e.restarts,
      frame.when(e.lastRestart, e.time, e.tz)), width), C.warn)
    y = y + 1
  end
  if e.muted then
    local left = e.muted.left and (frame.ago(e.muted.left) .. " left") or "until it clears"
    local x = 2
    f:text(x, y, Gui.fit(("MUTED by %s, %s"):format(tostring(e.muted.by or "?"), left), width - 11), C.warn)
    if e.canMute then f:button(f.w - 9, y, "UNMUTE", actions.nodeUnmute, C.line) end
    y = y + 1
  elseif e.canMute then
    f:text(2, y, "MUTE", C.accent)
    local bx = 8
    bx = f:button(bx, y, "1 H", function(p) actions.nodeMute(p, 3600) end)
    bx = f:button(bx, y, "4 H", function(p) actions.nodeMute(p, 4 * 3600) end)
    f:button(bx, y, "UNTIL IT CLEARS", function(p) actions.nodeMute(p, false) end)
    y = y + 1
    f:text(2, y, Gui.fit("Alerts stay listed, but don't beep, show in HUDs or count to health.", width), C.dim)
    y = y + 1
  end
  y = y + 1

  f:heading(2, y, ("ALERTS (%d)"):format(#e.alerts), width)
  y = y + 1
  if #e.alerts == 0 then f:text(2, y, "All quiet.", C.dim); y = y + 1 end
  for i, a in ipairs(e.alerts) do
    if i > 5 then f:text(2, y, ("+%d more"):format(#e.alerts - 5), C.dim); y = y + 1; break end
    local tag = Gui.fit(a.level == "bad" and " BAD" or " WARN", 6)
    local quiet = a.acked or a.muted
    if quiet then f:text(2, y, tag, C.dim) else f:text(2, y, tag, C.bg, a.level == "bad" and C.bad or C.warn) end
    local when = (a.muted and "muted · " or "") .. "for " .. frame.ago(e.time - a.since)
    local chip = ""
    if e.canMute and not e.muted then chip = a.muted and "UNMUTE" or "MUTE" end
    local right = f.w - (chip ~= "" and Gui.len(chip) + 3 or 0)
    local label = (a.acked and ("✓ " .. (a.ackedBy and (a.ackedBy .. "  ") or "")) or "") .. a.text
    f:text(9, y, Gui.fit(label, right - 9 - Gui.len(when) - 1), quiet and C.dim or C.text)
    f:text(right - Gui.len(when), y, when, C.dim)
    local ackKey = a.key
    f:hit(2, y, right - 1, y, function(p) actions.ack(ackKey, p) end)
    if chip ~= "" then
      local key = a.key
      f:button(f.w - Gui.len(chip) - 1, y, chip, function(p)
        if a.muted then actions.alertUnmute(p, key) else actions.alertMute(p, key) end
      end, C.line)
    end
    y = y + 1
  end
  y = y + 1

  f:heading(2, y, "LAST 24 HOURS", 13)
  f:text(17, y, Gui.fit(("a column is %d minutes"):format(math.floor((e.step or 0) / 60 + 0.5)), f.w - 17), C.dim)
  y = y + 1
  for _, tk in ipairs(e.ticks or {}) do f:text(BAND - 1 + tk[1], y, tk[2], C.dim) end
  y = y + 1
  f:text(2, y, Gui.fit(e.name, BAND - 3), C.dim)
  local cols = f.w - BAND
  local band = e.band or { cells = {}, marks = {} }
  local c = 1
  while c <= cols do
    local level, mark = band.cells[c], band.marks[c]
    local stop = c
    if not mark then
      while stop < cols and band.cells[stop + 1] == level and not band.marks[stop + 1] do stop = stop + 1 end
    end
    local bg = level == "bad" and C.bad or level == "warn" and C.warn or C.panel
    f:text(BAND - 1 + c, y, mark and "│" or string.rep(" ", stop - c + 1), C.text, bg)
    c = stop + 1
  end
  y = y + 2

  -- Used by goes last but its rows are kept: metrics take what's left.
  local usedRows = 2
  f:heading(2, y, ("METRICS (%d)"):format(#e.metrics), width)
  y = y + 1
  local room = last - usedRows - y
  for i, m in ipairs(e.metrics) do
    if i > room then f:text(2, y, ("+%d more: DATA lists them all"):format(#e.metrics - i + 1), C.dim); y = y + 1; break end
    local right = ("%s · %d series"):format(m.type, m.series)
    f:text(2, y, Gui.fit(m.name .. (m.unit and ("  " .. m.unit) or ""), width - Gui.len(right) - 1), C.text)
    f:text(f.w - Gui.len(right), y, right, C.dim)
    y = y + 1
  end
  y = y + 1
  if y + 1 <= last + 1 then
    f:heading(2, y, "READ BY", 7)
    f:text(11, y, Gui.fit(#e.usedBy > 0 and table.concat(e.usedBy, ", ") or "no view yet", f.w - 11),
      #e.usedBy > 0 and C.text or C.dim)
  end
  f:editorFooter(e, "can use this")
end

return node
