--[[ lens.hub.dashboard: the hub's screen. Draws a model; knows nothing about the network.

  local d = require("lens.hub.dashboard").new(gpu, w, h)
  d:draw(model, actions)   build the frame and send the GPU only the rows that changed since the last draw
  d:tap(x, y) -> bool      run the touch target under (x, y)
  d:invalidate()           forget what's on screen, so the next draw repaints every row

  model = {
    now, port, node, health = "ok" | "warn" | "bad", missingConfig = bool,
    nodes  = store:nodes(now),
    alerts = alerts:list(), counts = alerts:counts(),
    panels = { { label, text, frac = 0..1 | nil, level = "warn" | "bad" | nil, history = { number... } } },
  }
  actions = { ack(key), ackAll(), quit() }

  Layout: 120 columns or more puts nodes and alerts on the left and panels (in two columns when there's room)
  on the right; narrower screens stack panels, nodes and alerts. Lists that don't fit end with "+N more".
]]

local Gui = require("lens.gui")

local dashboard = {}

local C = Gui.C
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇" }
local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad, stale = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD", stale = "STALE" }

local function ago(s)
  s = math.max(0, math.floor(s or 0))
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return ("%dh%02dm"):format(s // 3600, (s % 3600) // 60)
end
dashboard.ago = ago

---------------------------------------------------------------- frame building
local Frame = {}
Frame.__index = Frame

local function newFrame(w, h)
  local rows = {}
  for y = 1, h do rows[y] = { bg = C.bg, segs = {} } end
  return setmetatable({ w = w, h = h, rows = rows, hits = {} }, Frame)
end

function Frame:text(x, y, s, fg, bg)
  if y < 1 or y > self.h or x > self.w then return end
  local room = self.w - x + 1
  if Gui.len(s) > room then s = Gui.fit(s, room) end
  local segs = self.rows[y].segs
  segs[#segs + 1] = { x, s, fg or C.text, bg or self.rows[y].bg }
end

function Frame:rowBg(y, bg) if self.rows[y] then self.rows[y].bg = bg end end
function Frame:hit(x1, y1, x2, y2, fn) self.hits[#self.hits + 1] = { x1, y1, x2, y2, fn } end

function Frame:button(x, y, label, fn, color)
  local s = " " .. label .. " "
  self:text(x, y, s, C.text, color or C.btn)
  if fn then self:hit(x, y, x + Gui.len(s) - 1, y, fn) end
  return x + Gui.len(s) + 1
end

local function rowKey(row)
  local parts = { row.bg }
  for _, s in ipairs(row.segs) do parts[#parts + 1] = s[1] .. "\1" .. s[2] .. "\1" .. s[3] .. "\1" .. s[4] end
  return table.concat(parts, "\2")
end

---------------------------------------------------------------- sections
local function header(f, m, actions)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LENS", C.accent, C.panel)
  local hc = HEALTH_COLOR[m.health] or C.dim
  f:text(8, 1, " " .. (HEALTH_TEXT[m.health] or "?") .. " ", C.bg, hc)
  local c = m.counts or { bad = 0, warn = 0 }
  local summary = ("%d node%s   alerts: %d bad, %d warn"):format(#m.nodes, #m.nodes == 1 and "" or "s", c.bad, c.warn)
  f:text(17, 1, summary, C.text, C.panel)
  local right = ("%s · port %d"):format(m.node or "hub", m.port or 0)
  local qx = f.w - 7
  f:text(qx - Gui.len(right) - 2, 1, right, C.dim, C.panel)
  f:button(qx, 1, "QUIT", actions.quit, C.line)
end

local function heading(f, x, y, text, width)
  f:text(x, y, Gui.fit(text, width), C.accent)
end

local function nodes(f, m, x, y, width, maxRows)
  heading(f, x, y, "NODES", width)
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
    local seen = n.lastSeen and (ago(m.now - n.lastSeen) .. " ago") or "never"
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
  heading(f, x, y, ("ALERTS (%d)"):format(#list), width)
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
    local tagColor = a.level == "bad" and C.bad or C.warn
    if a.acked then
      f:text(x, y, Gui.fit(a.level == "bad" and " BAD" or " WARN", 6), C.dim)
    else
      f:text(x, y, Gui.fit(a.level == "bad" and " BAD" or " WARN", 6), C.bg, tagColor)
    end
    local age = ago(m.now - (a.since or m.now))
    local textW = width - 7 - 7
    local label = (a.acked and "✓ " or "") .. a.text
    if a.node and not a.text:find(a.node, 1, true) then label = label .. "  · " .. a.node end
    f:text(x + 7, y, Gui.fit(label, textW), a.acked and C.dim or C.text)
    f:text(x + width - 6, y, Gui.rfit(age, 6), C.dim)
    local key = a.key
    f:hit(x, y, x + width - 1, y, function() actions.ack(key) end)
    y = y + 1
  end
  if shown < #list then f:text(x, y, ("+%d more"):format(#list - shown), C.dim) end
end

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

-- One panel: label and value, a bar when it has a fraction, a sparkline when tall enough.
local function panel(f, p, x, y, width, tall)
  local color = p.level == "bad" and C.bad or p.level == "warn" and C.warn or C.text
  local text = p.text or "–"
  f:text(x, y, Gui.fit(p.label, width - Gui.len(text) - 1), C.dim)
  f:text(x + width - Gui.len(text), y, text, color)
  local barColor = p.level == "bad" and C.bad or p.level == "warn" and C.warn or C.info
  if p.frac then
    local filled = math.floor(math.max(0, math.min(1, p.frac)) * width + 0.5)
    if filled > 0 then f:text(x, y + 1, string.rep(" ", filled), C.text, barColor) end
    if filled < width then f:text(x + filled, y + 1, string.rep(" ", width - filled), C.text, C.line) end
  else
    f:text(x, y + 1, string.rep("─", width), C.line)
  end
  if tall then f:text(x, y + 2, spark(p.history or {}, width), C.info) end
end

local function panels(f, m, x, y, width, lastRow, tall)
  heading(f, x, y, "PANELS", width)
  y = y + 1
  if #m.panels == 0 then
    if m.missingConfig then
      f:text(x, y, Gui.fit("No panels yet: copy /home/lens-hub.example.cfg to /home/lens-hub.cfg and edit it.", width), C.dim)
    else
      f:text(x, y, Gui.fit("No panels in lens-hub.cfg.", width), C.dim)
    end
    return y + 2
  end
  local cols = width >= 90 and 2 or 1
  local pw = (width - (cols - 1) * 3) // cols
  local step = tall and 4 or 3
  local i = 0
  for _, p in ipairs(m.panels) do
    local row, col = i // cols, i % cols
    local py = y + row * step
    if py + step - 2 > lastRow then
      f:text(x, lastRow, ("+%d more panels"):format(#m.panels - i), C.dim)
      return lastRow + 1
    end
    panel(f, p, x + col * (pw + 3), py, pw, tall)
    i = i + 1
  end
  return y + ((#m.panels + cols - 1) // cols) * step
end

---------------------------------------------------------------- drawing
local Dash = {}
Dash.__index = Dash

function dashboard.new(gpu, w, h)
  local ui = Gui.new(gpu, w, h)
  return setmetatable({ ui = ui, w = w, h = h, last = {}, hits = {} }, Dash)
end

function Dash:invalidate() self.last = {} end

function Dash:build(m, actions)
  local f = newFrame(self.w, self.h)
  header(f, m, actions)
  local lastRow = self.h - 1
  if self.w >= 120 then
    local lw = 56
    local rx = 2 + lw + 3
    local y = nodes(f, m, 2, 3, lw, math.max(3, (self.h - 6) // 2))
    alerts(f, m, actions, 2, y + 1, lw, lastRow)
    panels(f, m, rx, 3, self.w - rx, lastRow, true)
  else
    local width = self.w - 2
    local y = panels(f, m, 2, 3, width, self.h - 10, false)    -- leave nodes and alerts 10 rows
    y = nodes(f, m, 2, y + 1, width, 5)
    alerts(f, m, actions, 2, y + 1, width, lastRow)
  end
  f:rowBg(self.h, C.bg)
  f:text(2, self.h, Gui.fit("Tap an alert to acknowledge it.", self.w - 2), C.dim)
  return f
end

-- Same background and the same segments at the same places with the same widths: only texts or colors
-- changed, so those segments can be redrawn in place.
local function sameShape(a, b)
  if not a or a.bg ~= b.bg or #a.segs ~= #b.segs then return false end
  for i, sa in ipairs(a.segs) do
    local sb = b.segs[i]
    if sa[1] ~= sb[1] or Gui.len(sa[2]) ~= Gui.len(sb[2]) then return false end
  end
  return true
end

function Dash:draw(m, actions)
  local f = self:build(m, actions)
  local ui = self.ui
  for y = 1, self.h do
    local row = f.rows[y]
    local key = rowKey(row)
    local last = self.last[y]
    if not last or last.key ~= key then
      if sameShape(last and last.row, row) then
        for i, sg in ipairs(row.segs) do
          local old = last.row.segs[i]
          if old[2] ~= sg[2] or old[3] ~= sg[3] or old[4] ~= sg[4] then ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
        end
      else
        ui.fill(1, y, self.w, 1, row.bg)
        for _, sg in ipairs(row.segs) do ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
      end
      self.last[y] = { key = key, row = row }
    end
  end
  self.hits = f.hits
end

function Dash:tap(x, y)
  for i = #self.hits, 1, -1 do
    local h = self.hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
      if h[5] then h[5]() end
      return true
    end
  end
  return false
end

function Dash:restore() self.ui.restore() end

return dashboard
