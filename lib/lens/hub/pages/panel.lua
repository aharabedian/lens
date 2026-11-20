--[[ lens.hub.pages.panel: the panel page (lens.hub.editors.panel): one view up close. Its value, its history as a
  chart (12 rows on screens 40 or taller, else 5) with the high and low at the right and the alerts that started
  meanwhile under it, low / average / high, its query with what each part comes to and which nodes send it, its
  status rules (▶ the one that set the dot), where it's shown, and EDIT VIEW / SAVE AS ALERT / ADD TO MY HUD.

  panel.draw(f, e, actions)   e: the editor's model (its header comment), plus player, error, closesIn.
                              Sections that don't fit are left off the bottom.
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")
local unicode = require("unicode")

local panel = {}

local C = frame.C
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇" }
local RESULT_COLOR = { yes = C.text, no = C.dim, ["no data"] = C.dim, ["not tried"] = C.dim }
local LEVEL_NAME = { good = "Green", warn = "Yellow", bad = "Red", off = "Gray" }

-- Values averaged into at most `cols` columns -> list of numbers or false.
local function columns(history, cols)
  local n = #history
  local per = math.max(1, math.ceil(n / cols))
  local out = {}
  for first = 1, n, per do
    local sum, k = 0, 0
    for i = first, math.min(n, first + per - 1) do
      if type(history[i]) == "number" then sum, k = sum + history[i], k + 1 end
    end
    out[#out + 1] = k > 0 and sum / k or false
  end
  return out, per
end

-- The chart from row y, `rows` tall -> the row after its time axis.
local function chart(f, e, y, rows)
  local cols = f.w - 9
  local data, per = columns(e.history, cols)
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(data) do if v then lo, hi = math.min(lo, v), math.max(hi, v) end end
  if lo == math.huge then
    f:text(2, y, "No samples yet.", C.dim)
    return y + 1
  end
  local levels = rows * #SPARK
  local lines = {}
  for r = 1, rows do lines[r] = {} end
  local x0 = cols - #data            -- the newest sample at the right edge
  for i, v in ipairs(data) do
    for r = 1, rows do lines[r][x0 + i] = " " end
    if v then
      local p = hi == lo and 0 or math.floor((v - lo) / (hi - lo) * (levels - 1) + 0.5)
      local r = rows - p // #SPARK
      lines[r][x0 + i] = SPARK[p % #SPARK + 1]
    end
  end
  for r = 1, rows do
    local s = {}
    for c = 1, cols do s[c] = lines[r][c] or " " end
    f:text(2, y + r - 1, table.concat(s), C.info)
  end
  local st = e.stats or {}
  f:text(f.w - 6, y, Gui.rfit(st.high or "", 6), C.dim)
  f:text(f.w - 6, y + rows - 1, Gui.rfit(st.low or "", 6), C.dim)
  y = y + rows
  local span = #e.history * (e.sample or 10)
  f:text(2 + x0, y, frame.when(e.time - span, e.time, e.tz), C.dim)
  f:text(cols - 1, y, "now", C.dim)
  return y + 1, per
end

-- Text wrapped to width, at most `max` lines.
local function wrap(text, width, max)
  local out = {}
  local s = tostring(text)
  while #out < max and Gui.len(s) > 0 do
    if Gui.len(s) <= width or #out == max - 1 then
      out[#out + 1] = Gui.fit(s, width)
      break
    end
    out[#out + 1] = unicode.sub(s, 1, width)
    s = unicode.sub(s, width + 1)
  end
  return out
end

function panel.draw(f, e, actions)
  local buttons = { { "DONE", actions.panelDone } }
  if e.canEdit and not e.missing then table.insert(buttons, 1, { "EDIT VIEW", actions.panelEdit }) end
  f:editorHeader("Panel: " .. tostring(e.label), buttons)
  local last = f.h - 2
  if e.missing then
    f:text(2, 3, Gui.fit("This view is gone: it was deleted or renamed.", f.w - 2), C.dim)
    f:editorFooter(e, "can use this")
    return
  end
  local width = f.w - 2
  local p = e.shown or {}
  local x = 2
  if p.status then f:text(2, 3, "●", frame.levelColor(p.status, C.dim)); x = 4 end
  local text = p.text or "–"
  f:text(x, 3, Gui.fit(e.label, width - Gui.len(text) - x), C.text)
  f:text(f.w - Gui.len(text), 3, text, frame.levelColor(p.level, C.text))

  local y = 5
  local minutes = math.floor(#e.history * (e.sample or 10) / 60 + 0.5)
  f:heading(2, y, ("LAST %d MINUTES"):format(minutes), 18)
  f:text(20, y, Gui.fit(("one sample every %d s"):format(e.sample or 10), f.w - 20), C.dim)
  local rows = f.h >= 40 and 12 or 5
  y = chart(f, e, y + 1, rows)
  local shownAlerts = 0
  for i = #e.alerts, 1, -1 do
    if shownAlerts == 3 or y > last then break end
    local a = e.alerts[i]
    local label = a.text .. ((a.node and not a.text:find(a.node, 1, true)) and ("  · " .. a.node) or "")
    f:text(2, y, "▲", a.level == "bad" and C.bad or C.warn)
    local when = frame.when(a.since, e.time, e.tz)
    f:text(4, y, when, C.dim)
    f:text(5 + Gui.len(when), y, Gui.fit(label, width - 4 - Gui.len(when)), C.text)
    y, shownAlerts = y + 1, shownAlerts + 1
  end
  y = y + 1

  local function room(n) return y + (n or 1) - 1 <= last end
  if e.stats and room() then
    local s = e.stats
    f:text(2, y, Gui.fit(("low %s   average %s   high %s   now %s"):format(s.low, s.average, s.high, s.last), width), C.text)
    y = y + 2
  end
  if e.query and room(3) then
    f:heading(2, y, "QUERY", 5)
    y = y + 1
    for _, l in ipairs(wrap(e.query.text, width, 2)) do f:text(2, y, l, C.text); y = y + 1 end
    local equals = e.query.parts and ("= %s = %s"):format(e.query.parts, e.query.value) or ("= " .. e.query.value)
    f:text(2, y, Gui.fit(equals, width), C.text)
    y = y + 1
    if #e.query.nodes > 0 and room() then
      f:text(2, y, Gui.fit("from " .. table.concat(e.query.nodes, ", "), width), C.dim)
      y = y + 1
    end
    y = y + 1
  end
  if e.of and room(2) then
    f:text(2, y, "of", C.accent)
    f:text(5, y, Gui.fit(("%s = %s"):format(e.of.text, e.of.value), width - 3), C.text)
    y = y + 2
  end
  if e.values and room(2) then
    f:heading(2, y, "VALUES", 6)
    y = y + 1
    for _, v in ipairs(e.values) do
      if not room() then break end
      f:text(2, y, Gui.fit(("%s = %s = %s"):format(v.name, v.text, v.value), width), C.text)
      y = y + 1
    end
    y = y + 1
  end
  if e.status and room(3) then
    f:heading(2, y, "STATUS", 6)
    f:text(10, y, Gui.fit("rules in order; the first true one sets the dot", f.w - 10), C.dim)
    y = y + 1
    local first
    for i, r in ipairs(e.status) do
      if not room() then break end
      if r.first then first = i; f:text(2, y, "▶", C.accent) end
      f:text(5, y, Gui.fit(r.level, 5), frame.levelColor(r.level, C.dim))
      f:text(11, y, Gui.fit(r.text, width - 22), r.first and C.text or C.dim)
      f:text(f.w - 9, y, Gui.rfit(r.result, 9), RESULT_COLOR[r.result] or C.dim)
      y = y + 1
    end
    if room() then
      local note
      if first then
        note = ("%s: rule %d is the first true one."):format(LEVEL_NAME[e.status[first].level] or "?", first)
      else
        note = "None is true: the dot is gray."
      end
      f:text(2, y, Gui.fit(note, width), C.dim)
      y = y + 1
    end
    y = y + 1
  end
  if room(2) then
    f:heading(2, y, "SHOWN ON", 8)
    y = y + 1
    local parts = {}
    if #e.shownOn.pages > 0 then parts[#parts + 1] = "Dashboard: " .. table.concat(e.shownOn.pages, ", ") end
    if #e.shownOn.huds > 0 then parts[#parts + 1] = "HUD: " .. table.concat(e.shownOn.huds, ", ") end
    f:text(2, y, Gui.fit(#parts > 0 and table.concat(parts, " · ") or "Nowhere: it's only in the library.", width),
      C.text)
    y = y + 2
  end
  if room() then
    local bx = 2
    if e.canEdit then bx = f:button(bx, y, "SAVE AS ALERT", actions.panelAlert) end
    if e.canHud then f:button(bx, y, "ADD TO MY HUD", actions.panelHud) end
  end
  f:editorFooter(e, "can use this")
end

return panel
