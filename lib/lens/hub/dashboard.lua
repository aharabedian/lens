--[[ lens.hub.dashboard: the hub's screen. Draws a model; knows nothing about the network.

  local d = require("lens.hub.dashboard").new(gpu, w, h)
  d:draw(model, actions)   build the frame and send the GPU only the rows that changed since the last draw
  d:tap(x, y, player?) -> bool   run the touch target under (x, y); it gets the player who tapped
  d:restore()              plain terminal colors again (on exit)

  model = {
    now, port, node, version, health = "ok" | "warn" | "bad", missingConfig = bool,
    nodes  = store:nodes(now),
    alerts = alerts:list(), counts = alerts:counts(),
    panels = { { label, text, frac = 0..1 | nil, level = "warn" | "bad" | nil, history = { number... } } },
    hudError = text | nil,   shown in the footer
    hudPerMinute = n | nil,  HUD component calls in the last minute, shown in the footer
    huds = bool,             Glasses Terminals attached: the header has a HUD button (EDIT is always there)
    notice = text | nil,     shown in the footer (who has the editor, who may edit)
    dashEdit = nil | { player, panels = { panel... }, library = { { label, source }... }, canUndo, error,
                       closesIn }   the EDIT page: the dashboard's panels and the views not on it
    viewEdit = nil | { player, old = label | nil (new), source, fields = { { key, name, kind, text }... },
                       focus = key, preview = { text, frac, level } | { error }, keyboard = bool, error,
                       closesIn }   one view's fields
    editor = nil | { player, own, scale, blocks = n, block = i (being edited), anchor, x, y, width, step,
                     rows = { { index, kind, label?, count? }... } (the block's elements), hidden = { label... },
                     wearing = n, error = text | nil, closesIn = seconds }   the HUD editor, drawn instead
  }
  actions = { ack(key), ackAll(), quit(), hud(player), and the editor's (each gets the tapping player first):
              hudDone, hudReset, hudBlock(i), hudBlockAdd, hudBlockRemove, hudToggle(label), hudKind(i),
              hudMove(i, -1 | 1), hudAlerts(-1 | 1), hudGap, hudRemove(i), hudAnchor(anchor), hudNudge(dx, dy),
              hudStepSize, hudWidth(-1 | 1), hudScale(-1 | 1),
              edit(player), dashDone, dashUndo, dashMove(i, -1 | 1), dashRemove(i), dashAdd(label), dashView(label),
              dashNew, viewFocus(key), viewCycle(key), viewSave, viewCancel, viewDelete }

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
local function heading(f, x, y, text, width)
  f:text(x, y, Gui.fit(text, width), C.accent)
end

local function header(f, m, actions)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LENS", C.accent, C.panel)
  local hc = HEALTH_COLOR[m.health] or C.dim
  f:text(8, 1, " " .. (HEALTH_TEXT[m.health] or "?") .. " ", C.bg, hc)
  local c = m.counts or { bad = 0, warn = 0 }
  local summary = ("%d node%s   alerts: %d bad, %d warn"):format(#m.nodes, #m.nodes == 1 and "" or "s", c.bad, c.warn)
  f:text(17, 1, summary, C.text, C.panel)
  local right = ("%s · port %d · v%s"):format(m.node or "hub", m.port or 0, m.version or "?")
  local qx = f.w - 7
  local rx = qx
  if m.huds then
    rx = qx - 6
    f:button(rx, 1, "HUD", actions.hud, C.btnOn)
  end
  rx = rx - 7
  f:button(rx, 1, "EDIT", actions.edit, C.btnOn)
  local room = rx - 2 - (17 + Gui.len(summary) + 2)
  if Gui.len(right) > room then right = "v" .. (m.version or "?") end   -- narrow: just the version
  if Gui.len(right) <= room then f:text(rx - Gui.len(right) - 2, 1, right, C.dim, C.panel) end
  f:button(qx, 1, "QUIT", actions.quit, C.line)
end

---------------------------------------------------------------- editors' frame
local function editorHeader(f, title, buttons)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LENS", C.accent, C.panel)
  local x = f.w
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    x = x - Gui.len(b[1]) - 3
    f:button(x, 1, b[1], b[2], b[3] or C.btnOn)
  end
  f:text(8, 1, Gui.fit(title, math.max(1, x - 10)), C.text, C.panel)
end

local function editorFooter(f, e)
  f:rowBg(f.h, C.bg)
  if e.error then
    f:text(2, f.h, Gui.fit(e.error, f.w - 2), C.bad)
  else
    f:text(2, f.h, Gui.fit(("Only %s can change this. Closes in %ds without a tap."):format(tostring(e.player or "?"),
      e.closesIn or 0), f.w - 2), C.dim)
  end
end

---------------------------------------------------------------- the dashboard's EDIT page
local function dashEditor(f, m, actions)
  local e = m.dashEdit
  local buttons = {}
  if e.canUndo then buttons[#buttons + 1] = { "UNDO", actions.dashUndo, C.line } end
  buttons[#buttons + 1] = { "DONE", actions.dashDone }
  editorHeader(f, "Edit the dashboard", buttons)
  local wide = f.w >= 100
  local lw = wide and (f.w - 6) // 2 or f.w - 2
  local lx, rx = 2, wide and (2 + lw + 3) or 2
  local last = f.h - 2

  heading(f, lx, 3, ("ON THE DASHBOARD (%d)"):format(#e.panels), lw)
  local y = 4
  if #e.panels == 0 then f:text(lx, y, "Nothing yet: add a view from the library.", C.dim); y = y + 1 end
  local labelW = lw - 32
  for i, p in ipairs(e.panels) do
    if y > last then break end
    local color = p.level == "bad" and C.bad or p.level == "warn" and C.warn or p.level == "good" and C.good or C.text
    f:text(lx, y, Gui.fit(p.label, labelW), C.text)
    f:text(lx + labelW + 1, y, Gui.rfit(p.text or "–", 10), color)
    local bx = lx + lw - 19
    local label = p.label
    f:button(bx, y, "EDIT", function(pl) actions.dashView(pl, label) end)
    if i > 1 then f:button(bx + 7, y, "▲", function(pl) actions.dashMove(pl, i, -1) end) end
    if i < #e.panels then f:button(bx + 11, y, "▼", function(pl) actions.dashMove(pl, i, 1) end) end
    f:button(bx + 15, y, "✕", function(pl) actions.dashRemove(pl, i) end, C.line)
    y = y + 1
  end

  local ly = wide and 3 or y + 1
  heading(f, rx, ly, ("LIBRARY (%d)"):format(#e.library), lw - 12)
  f:button(rx + lw - 10, ly, "+ NEW", actions.dashNew)
  y = ly + 1
  if #e.library == 0 then f:text(rx, y, Gui.fit("Every view is on the dashboard.", lw), C.dim) end
  for k, v in ipairs(e.library) do
    if y > last then
      f:text(rx, last + 1, ("+%d more"):format(#e.library - k + 1), C.dim)
      break
    end
    local label = v.label
    f:button(rx, y, "+", function(pl) actions.dashAdd(pl, label) end)
    f:text(rx + 4, y, Gui.fit(label, lw - 22), C.text)
    f:text(rx + lw - 17, y, v.source == "screen" and "" or (v.source == "edited" and "cfg*" or "cfg"), C.dim)
    f:button(rx + lw - 7, y, "EDIT", function(pl) actions.dashView(pl, label) end)
    y = y + 1
  end
  editorFooter(f, e)
end

---------------------------------------------------------------- the view editor
local function viewEditor(f, m, actions)
  local e = m.viewEdit
  editorHeader(f, e.old and ("View: " .. e.old) or "New view",
    { { "SAVE", actions.viewSave }, { "CANCEL", actions.viewCancel, C.line } })
  local nx, fx = 2, 15
  local fw = f.w - fx - 1
  local y = 3
  for _, fd in ipairs(e.fields) do
    local key = fd.key
    f:text(nx, y, Gui.fit(fd.name, fx - nx - 1), C.dim)
    if fd.kind == "choice" then
      f:button(fx, y, Gui.fit(fd.text, 10), function(pl) actions.viewCycle(pl, key) end, C.sel)
    else
      local focused = e.focus == key
      local shown = fd.text .. (focused and "▏" or "")
      if Gui.len(shown) > fw then shown = "…" .. require("unicode").sub(shown, -(fw - 1)) end
      f:text(fx, y, Gui.fit(shown, fw), focused and C.text or C.dim, focused and C.sel or C.field)
      f:hit(fx, y, fx + fw - 1, y, function(pl) actions.viewFocus(pl, key) end)
    end
    y = y + 1
  end
  y = y + 1
  f:text(nx, y, "Now", C.accent)
  local pv = e.preview or {}
  if pv.error then
    f:text(fx, y, Gui.fit(pv.error, fw), C.bad)
  else
    local color = pv.level == "bad" and C.bad or pv.level == "warn" and C.warn or pv.level == "good" and C.good or C.text
    f:text(fx, y, Gui.fit(pv.text or "–", 16), color)
    if pv.frac then
      local bw = math.max(0, fw - 18)
      local filled = math.floor(math.max(0, math.min(1, pv.frac)) * bw + 0.5)
      if filled > 0 then f:text(fx + 18, y, string.rep(" ", filled), C.text, color == C.text and C.info or color) end
      if filled < bw then f:text(fx + 18 + filled, y, string.rep(" ", bw - filled), C.text, C.line) end
    end
  end
  y = y + 2
  if e.keyboard then
    f:text(nx, y, Gui.fit("Tap a field and type. Enter: the next field. Insert pastes your clipboard.", f.w - 2), C.dim)
  else
    f:text(nx, y, Gui.fit("No keyboard on this screen: attach one to type into the fields.", f.w - 2), C.warn)
  end
  y = y + 1
  if e.source == "config" or e.source == "edited" then
    f:text(nx, y, Gui.fit("From lens-hub.cfg: your changes are kept on the screen's side.", f.w - 2), C.dim)
    y = y + 1
  end
  if e.old and e.source ~= "config" then
    f:button(nx, y + 1, e.source == "edited" and "BACK TO lens-hub.cfg" or "DELETE VIEW", actions.viewDelete, C.line)
  end
  editorFooter(f, e)
end

---------------------------------------------------------------- the HUD editor
local ARROWS = { ["top-left"] = "↖", top = "↑", ["top-right"] = "↗", left = "←", center = "•", right = "→",
  ["bottom-left"] = "↙", bottom = "↓", ["bottom-right"] = "↘" }
local GRID = { "top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right" }

local function stepper(f, x, y, label, value, minus, plus)
  f:text(x, y, Gui.fit(label, 8), C.dim)
  f:button(x + 9, y, "-", minus)
  f:text(x + 13, y, Gui.rfit(value, 5), C.text)
  f:button(x + 19, y, "+", plus)
end

local function editor(f, m, actions)
  local e = m.editor
  editorHeader(f, "HUD for " .. tostring(e.player or "?"), { { "DONE", actions.hudDone } })

  -- Blocks: one tab each, add, remove.
  f:text(2, 3, "BLOCKS", C.accent)
  local bx = 9
  for i = 1, e.blocks do
    bx = f:button(bx, 3, tostring(i), function(p) actions.hudBlock(p, i) end, i == e.block and C.btnOn or C.btn)
  end
  if e.blocks < 6 then bx = f:button(bx, 3, "+", actions.hudBlockAdd) end
  if e.blocks > 1 then f:button(bx + 1, 3, "REMOVE " .. e.block, actions.hudBlockRemove, C.line) end

  -- The block's elements, then what could be added.
  local lx, lw = 2, math.min(46, f.w - 36)
  f:text(lx, 5, Gui.fit(("IN BLOCK %d"):format(e.block), lw), C.accent)
  local y, last = 6, f.h - 2
  local function room(n)
    if y > last then
      f:text(lx, last + 1, ("+%d more"):format(n), C.dim)
      return false
    end
    return true
  end
  local labelW = lw - 4 - 16
  for k, r in ipairs(e.rows) do
    if not room(#e.rows - k + 1 + #e.hidden) then return end
    local i = r.index
    f:text(lx, y, "[✓]", C.good)
    if r.kind == "alerts" then
      f:text(lx + 4, y, Gui.fit("Alerts", labelW - 6), C.text)
      f:hit(lx, y, lx + 9, y, function(p) actions.hudRemove(p, i) end)
      f:button(lx + lw - 21, y, "-", function(p) actions.hudAlerts(p, -1) end)
      f:text(lx + lw - 17, y, tostring(r.count), C.text)
      f:button(lx + lw - 15, y, "+", function(p) actions.hudAlerts(p, 1) end)
    elseif r.kind == "gap" then
      f:text(lx + 4, y, Gui.fit("(gap)", labelW), C.dim)
      f:hit(lx, y, lx + labelW + 3, y, function(p) actions.hudRemove(p, i) end)
    else
      local label = r.label
      f:text(lx + 4, y, Gui.fit(label, labelW), C.text)
      f:hit(lx, y, lx + labelW + 3, y, function(p) actions.hudToggle(p, label) end)
      f:button(lx + lw - 15, y, r.kind == "bar" and "BAR " or "TEXT", function(p) actions.hudKind(p, i) end,
        r.kind == "bar" and C.btnOn or C.sel)
    end
    if k > 1 then f:button(lx + lw - 8, y, "▲", function(p) actions.hudMove(p, i, -1) end) end
    if k < #e.rows then f:button(lx + lw - 4, y, "▼", function(p) actions.hudMove(p, i, 1) end) end
    y = y + 1
  end
  local hasAlerts = false
  for _, r in ipairs(e.rows) do if r.kind == "alerts" then hasAlerts = true end end
  for k, label in ipairs(e.hidden) do
    if not room(#e.hidden - k + 1) then return end
    f:text(lx, y, "[ ]", C.dim)
    f:text(lx + 4, y, Gui.fit(label, labelW), C.dim)
    f:hit(lx, y, lx + labelW + 3, y, function(p) actions.hudToggle(p, label) end)
    y = y + 1
  end
  if y <= last then
    local ax = lx
    if not hasAlerts then ax = f:button(ax, y, "+ ALERTS", function(p) actions.hudAlerts(p, 1) end) end
    f:button(ax, y, "+ GAP", actions.hudGap)
  end

  -- Where the block sits: an anchor, then nudges from it.
  local rx = lx + lw + 4
  f:text(rx, 5, "POSITION", C.accent)
  for k, a in ipairs(GRID) do
    local gx, gy = rx + ((k - 1) % 3) * 4, 6 + (k - 1) // 3
    f:button(gx, gy, ARROWS[a], function(p) actions.hudAnchor(p, a) end, e.anchor == a and C.btnOn or C.btn)
  end
  local nx = rx + 15
  f:button(nx + 4, 6, "▲", function(p) actions.hudNudge(p, 0, -1) end)
  f:button(nx, 7, "◀", function(p) actions.hudNudge(p, -1, 0) end)
  f:button(nx + 8, 7, "▶", function(p) actions.hudNudge(p, 1, 0) end)
  f:button(nx + 4, 8, "▼", function(p) actions.hudNudge(p, 0, 1) end)
  f:text(rx, 10, Gui.fit(("%s, x %d y %d"):format(e.anchor, e.x, e.y), 22), C.dim)
  f:button(rx + 23, 10, ("%dpx"):format(e.step), actions.hudStepSize, C.sel)
  stepper(f, rx, 12, "Width", tostring(e.width), function(p) actions.hudWidth(p, -1) end,
    function(p) actions.hudWidth(p, 1) end)
  stepper(f, rx, 13, "Size", ("%.2g"):format(e.scale), function(p) actions.hudScale(p, -1) end,
    function(p) actions.hudScale(p, 1) end)
  if e.own then f:button(rx, 15, "BACK TO DEFAULT", actions.hudReset, C.line) end
  local note
  if e.wearing == 0 then
    note = { "No terminal shows this HUD yet:", "link your glasses to one", "of your own." }
  else
    note = { ("Showing on %d terminal%s."):format(e.wearing, e.wearing == 1 and "" or "s"), "Changes apply at once." }
  end
  for i, l in ipairs(note) do f:text(rx, 16 + i, Gui.fit(l, f.w - rx), e.wearing == 0 and C.warn or C.dim) end
  editorFooter(f, e)
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
  local color = p.level == "bad" and C.bad or p.level == "warn" and C.warn or p.level == "good" and C.good or C.text
  local text = p.text or "–"
  f:text(x, y, Gui.fit(p.label, width - Gui.len(text) - 1), C.dim)
  f:text(x + width - Gui.len(text), y, text, color)
  local barColor = p.level == "bad" and C.bad or p.level == "warn" and C.warn or p.level == "good" and C.good or C.info
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
      f:text(x, y, Gui.fit("No panels yet: run lens-setup to add them.", width), C.dim)
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

function Dash:build(m, actions)
  local f = newFrame(self.w, self.h)
  if m.editor then
    editor(f, m, actions)
    return f
  elseif m.dashEdit then
    dashEditor(f, m, actions)
    return f
  elseif m.viewEdit then
    viewEditor(f, m, actions)
    return f
  end
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
    local tall = self.h >= 40                                  -- a portrait screen: sparklines, more nodes
    local y = panels(f, m, 2, 3, width, self.h - (tall and 16 or 10), tall)   -- leave nodes and alerts room
    y = nodes(f, m, 2, y + 1, width, tall and 6 or 5)
    alerts(f, m, actions, 2, y + 1, width, lastRow)
  end
  f:rowBg(self.h, C.bg)
  if m.notice then
    f:text(2, self.h, Gui.fit(m.notice, self.w - 2), C.warn)
  elseif m.hudError then
    f:text(2, self.h, Gui.fit("HUD: " .. m.hudError, self.w - 2), C.warn)
  else
    f:text(2, self.h, Gui.fit("Tap an alert to acknowledge it.", self.w - 2), C.dim)
  end
  if m.hudPerMinute then
    local s = ("HUD %d calls/min"):format(m.hudPerMinute)
    f:text(self.w - Gui.len(s), self.h, s, C.dim)
  end
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

function Dash:tap(x, y, player)
  for i = #self.hits, 1, -1 do
    local h = self.hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
      if h[5] then h[5](player) end
      return true
    end
  end
  return false
end

function Dash:restore() self.ui.restore() end

return dashboard
