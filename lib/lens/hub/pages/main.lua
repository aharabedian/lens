--[[ lens.hub.pages.main: the dashboard itself: header, nodes, alerts, panels, footer.

  main.draw(f, m, actions)   f: lens.hub.frame; m: the app's model (lens.hub.dashboard has its shape);
                             actions: ack(key), ackAll(), quit(), and the buttons that open editors: data, edit,
                             hud (each gets the tapping player)

  Panels whose `when` is false now (hidden) aren't shown. A panel shows state dots when its view has them.
  Layout: 120 columns or more puts nodes and alerts on the left and panels (in two columns when there's room)
  on the right; narrower screens stack panels, nodes and alerts, with sparklines when 40 rows or taller. Lists
  that don't fit end with "+N more".
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local main = {}

local C = frame.C
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇" }
local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad, stale = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD", stale = "STALE" }

local function header(f, m, actions)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LENS", C.accent, C.panel)
  local hc = HEALTH_COLOR[m.health] or C.dim
  f:text(8, 1, " " .. (HEALTH_TEXT[m.health] or "?") .. " ", C.bg, hc)
  local c = m.counts or { bad = 0, warn = 0 }
  local nodes = ("%d node%s"):format(#m.nodes, #m.nodes == 1 and "" or "s")
  local summary = ("%s   alerts: %d bad, %d warn"):format(nodes, c.bad, c.warn)
  -- Buttons from the right: QUIT, HUD (with terminals), EDIT, DATA.
  local qx = f.w - 7
  f:button(qx, 1, "QUIT", actions.quit, C.line)
  local rx = qx
  if m.huds then
    rx = rx - 6
    f:button(rx, 1, "HUD", actions.hud, C.btnOn)
  end
  rx = rx - 7
  f:button(rx, 1, "EDIT", actions.edit, C.btnOn)
  rx = rx - 7
  f:button(rx, 1, "DATA", actions.data, C.btnOn)
  if 17 + Gui.len(summary) + 1 > rx then summary = ("%s · %d bad %d warn"):format(nodes, c.bad, c.warn) end
  f:text(17, 1, Gui.fit(summary, math.max(1, rx - 18)), C.text, C.panel)
  -- The hub's name and port when there's room, else just the version, else nothing.
  local room = rx - 2 - (17 + Gui.len(summary) + 2)
  local right = ("%s · port %d · v%s"):format(m.node or "hub", m.port or 0, m.version or "?")
  if Gui.len(right) > room then right = "v" .. (m.version or "?") end
  if Gui.len(right) <= room then f:text(rx - Gui.len(right) - 2, 1, right, C.dim, C.panel) end
end

local function nodes(f, m, x, y, width, maxRows)
  f:heading(x, y, "NODES", width)
  y = y + 1
  if #m.nodes == 0 then
    f:text(x, y, Gui.fit(("Waiting for agents on port %d…"):format(m.port or 0), width), C.dim)
    return y + 1
  end
  local shown = #m.nodes
  if shown > maxRows then shown = maxRows - 1 end
  local nameW = math.max(8, math.min(20, width - 30))
  for i = 1, shown do
    local n = m.nodes[i]
    local hc = HEALTH_COLOR[n.health] or C.dim
    f:text(x, y, "●", hc)
    f:text(x + 2, y, Gui.fit(n.name, nameW), n.stale and C.dim or C.text)
    local cx = x + 3 + nameW
    f:text(cx, y, Gui.fit(n.role or "?", 7), C.dim)
    f:text(cx + 8, y, Gui.fit(HEALTH_TEXT[n.health] or "?", 6), hc)
    local seen = n.lastSeen and (frame.ago(m.now - n.lastSeen) .. " ago") or "never"
    f:text(cx + 15, y, Gui.rfit(seen, 8), n.stale and C.bad or C.dim)
    y = y + 1
  end
  if shown < #m.nodes then
    f:text(x, y, ("+%d more"):format(#m.nodes - shown), C.dim)
    y = y + 1
  end
  return y
end

local function alerts(f, m, actions, x, y, width, lastRow)
  local list = m.alerts or {}
  f:heading(x, y, ("ALERTS (%d)"):format(#list), width)
  if #list > 0 and (m.counts or {}).unacked and m.counts.unacked > 0 then
    f:button(x + width - 9, y, "ACK ALL", actions.ackAll)
  end
  y = y + 1
  if #list == 0 then
    f:text(x, y, "All quiet.", C.dim)
    return
  end
  local room = lastRow - y + 1
  local shown = math.min(#list, room)
  if shown < #list then shown = room - 1 end
  for i = 1, shown do
    local a = list[i]
    local tag = Gui.fit(a.level == "bad" and " BAD" or " WARN", 6)
    if a.acked then
      f:text(x, y, tag, C.dim)
    else
      f:text(x, y, tag, C.bg, a.level == "bad" and C.bad or C.warn)
    end
    local label = (a.acked and "✓ " or "") .. a.text
    if a.node and not a.text:find(a.node, 1, true) then label = label .. "  · " .. a.node end
    f:text(x + 7, y, Gui.fit(label, width - 14), a.acked and C.dim or C.text)
    f:text(x + width - 6, y, Gui.rfit(frame.ago(m.now - (a.since or m.now)), 6), C.dim)
    local key = a.key
    f:hit(x, y, x + width - 1, y, function() actions.ack(key) end)
    y = y + 1
  end
  if shown < #list then f:text(x, y, ("+%d more"):format(#list - shown), C.dim) end
end

-- The last `width` values of history, scaled between their own low and high.
local function spark(history, width)
  local n = #history
  if n == 0 then return "" end
  local first = math.max(1, n - width + 1)
  local lo, hi = math.huge, -math.huge
  for i = first, n do
    local v = history[i]
    if v then lo, hi = math.min(lo, v), math.max(hi, v) end
  end
  local out = {}
  for i = first, n do
    local v = history[i]
    if not v then
      out[#out + 1] = " "
    elseif hi == lo then
      out[#out + 1] = SPARK[1]
    else
      out[#out + 1] = SPARK[math.floor((v - lo) / (hi - lo) * (#SPARK - 1) + 0.5) + 1]
    end
  end
  return table.concat(out)
end

-- One panel: label and value, then state dots, a bar when it has a fraction, or a rule; a sparkline when tall.
local function panel(f, p, x, y, width, tall)
  local text = (p.text ~= "–" or not (p.dots or p.status)) and p.text or ""
  local lx = x
  if p.status then                                  -- the status dot leads the label
    f:text(x, y, "●", frame.levelColor(p.status, C.dim))
    lx = x + 2
  end
  f:text(lx, y, Gui.fit(p.label, width - Gui.len(text) - 1 - (lx - x)), C.dim)
  f:text(x + width - Gui.len(text), y, text, frame.levelColor(p.level, C.text))
  if p.dots then
    f:dots(x, y + 1, width, p.dots)
  elseif p.frac then
    local filled = math.floor(math.max(0, math.min(1, p.frac)) * width + 0.5)
    if filled > 0 then f:text(x, y + 1, string.rep(" ", filled), C.text, frame.levelColor(p.level, C.info)) end
    if filled < width then f:text(x + filled, y + 1, string.rep(" ", width - filled), C.text, C.line) end
  else
    f:text(x, y + 1, string.rep("─", width), C.line)
  end
  if tall then f:text(x, y + 2, spark(p.history or {}, width), C.info) end
end

local function panels(f, m, x, y, width, lastRow, tall)
  f:heading(x, y, "PANELS", width)
  y = y + 1
  local shown = {}
  for _, p in ipairs(m.panels) do if not p.hidden then shown[#shown + 1] = p end end
  if #m.panels == 0 then
    f:text(x, y, Gui.fit(m.missingConfig and "No panels yet: run lens-setup, or tap EDIT."
      or "No panels yet: tap EDIT to add some.", width), C.dim)
    return y + 2
  end
  if #shown == 0 then
    f:text(x, y, Gui.fit("Nothing to show right now.", width), C.dim)
    return y + 2
  end
  local cols = width >= 90 and 2 or 1
  local pw = (width - (cols - 1) * 3) // cols
  local step = tall and 4 or 3
  for i, p in ipairs(shown) do
    local row, col = (i - 1) // cols, (i - 1) % cols
    local py = y + row * step
    if py + step - 2 > lastRow then
      f:text(x, lastRow, ("+%d more panels"):format(#shown - i + 1), C.dim)
      return lastRow + 1
    end
    panel(f, p, x + col * (pw + 3), py, pw, tall)
  end
  return y + ((#shown + cols - 1) // cols) * step
end

local function footer(f, m)
  f:rowBg(f.h, C.bg)
  if m.notice then
    f:text(2, f.h, Gui.fit(m.notice, f.w - 2), C.warn)
  elseif m.hudError then
    f:text(2, f.h, Gui.fit("HUD: " .. m.hudError, f.w - 2), C.warn)
  else
    f:text(2, f.h, Gui.fit("Tap an alert to acknowledge it.", f.w - 2), C.dim)
  end
  if m.hudPerMinute then
    local s = ("HUD %d calls/min"):format(m.hudPerMinute)
    f:text(f.w - Gui.len(s), f.h, s, C.dim)
  end
end

function main.draw(f, m, actions)
  header(f, m, actions)
  local lastRow = f.h - 1
  if f.w >= 120 then
    local lw = 56
    local rx = 2 + lw + 3
    local y = nodes(f, m, 2, 3, lw, math.max(3, (f.h - 6) // 2))
    alerts(f, m, actions, 2, y + 1, lw, lastRow)
    panels(f, m, rx, 3, f.w - rx, lastRow, true)
  else
    local width = f.w - 2
    local tall = f.h >= 40
    local y = panels(f, m, 2, 3, width, f.h - (tall and 16 or 10), tall)   -- leave nodes and alerts room
    y = nodes(f, m, 2, y + 1, width, tall and 6 or 5)
    alerts(f, m, actions, 2, y + 1, width, lastRow)
  end
  footer(f, m)
end

return main
