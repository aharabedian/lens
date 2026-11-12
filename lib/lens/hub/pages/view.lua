--[[ lens.hub.pages.view: the view editor (lens.hub.editors.view): one view's fields, typed or cycled, and its
  value as it would show.

  view.draw(f, e, actions)   e: { player, old = label | nil (a new view), source = "config" | "edited" | "screen"
                             | nil, fields = { { key, name, kind, text } | { key, name, kind = "status" |
                             "states", rows = { { focus, level, text }... } }... }, focus, cursor,
                             preview = { text, frac, level, status?, dots?, hidden? } | { error }, keyboard,
                             error, closesIn }
  Text fields show a cursor where you type (tap to put it there; ← → Home End move it). Status rules and dot
  states are rows: tap a color to cycle good, warn, bad, off.
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local view = {}

local C = frame.C

local LEVEL_BG = { good = C.good, warn = C.warn, bad = C.bad, off = C.line }

-- A level as a chip to tap: its name on its color.
local function levelChip(f, x, y, level, fn)
  return f:button(x, y, Gui.fit(level, 4), fn, LEVEL_BG[level] or C.btn)
end

-- The status rules: + RULE, then a row each: level chip, query, ▲ ▼ ✕. Returns the next row.
local function ruleRows(f, e, fd, actions, nx, fx, fw, y)
  f:text(nx, y, Gui.fit(fd.name, fx - nx - 1), C.dim)
  f:button(fx, y, "+ RULE", actions.viewRuleAdd)
  if #fd.rows == 0 then f:text(fx + 10, y, Gui.fit("none: no status dot", fw - 10), C.dim) end
  y = y + 1
  for i, r in ipairs(fd.rows) do
    f:text(nx + 1, y, Gui.fit(i == 1 and "first true" or "else", fx - nx - 2), C.dim)
    local qx = levelChip(f, fx, y, r.level, function(pl) actions.viewRuleLevel(pl, i) end)
    local qw = fx + fw - qx - 13
    f:field(qx, y, qw, r.text, e.cursor, e.focus == r.focus, function(pl, pos) actions.viewFocus(pl, r.focus, pos) end)
    local bx = qx + qw + 1
    if i > 1 then f:button(bx, y, "▲", function(pl) actions.viewRuleMove(pl, i, -1) end) end
    if i < #fd.rows then f:button(bx + 4, y, "▼", function(pl) actions.viewRuleMove(pl, i, 1) end) end
    f:button(bx + 8, y, "✕", function(pl) actions.viewRuleRemove(pl, i) end, C.line)
    y = y + 1
  end
  return y
end

-- The dot states: + STATE, then a row each: state name, level chip, ✕. Returns the next row.
local function stateRows(f, e, fd, actions, nx, fx, fw, y)
  f:text(nx, y, Gui.fit(fd.name, fx - nx - 1), C.dim)
  f:button(fx, y, "+ STATE", actions.viewStateAdd)
  if #fd.rows == 0 then f:text(fx + 11, y, Gui.fit("none: the default states", fw - 11), C.dim) end
  y = y + 1
  for i, r in ipairs(fd.rows) do
    local nw = math.min(20, fw - 14)
    f:field(fx, y, nw, r.text, e.cursor, e.focus == r.focus, function(pl, pos) actions.viewFocus(pl, r.focus, pos) end)
    local cx = levelChip(f, fx + nw + 1, y, r.level, function(pl) actions.viewStateLevel(pl, i) end)
    f:button(cx, y, "✕", function(pl) actions.viewStateRemove(pl, i) end, C.line)
    y = y + 1
  end
  return y
end

local function fields(f, e, actions, nx, fx, fw)
  local y = 3
  for _, fd in ipairs(e.fields) do
    local key = fd.key
    if fd.kind == "status" then
      y = ruleRows(f, e, fd, actions, nx, fx, fw, y)
    elseif fd.kind == "states" then
      y = stateRows(f, e, fd, actions, nx, fx, fw, y)
    else
      f:text(nx, y, Gui.fit(fd.name, fx - nx - 1), C.dim)
      if fd.kind == "choice" then
        f:button(fx, y, Gui.fit(fd.text, 10), function(pl) actions.viewCycle(pl, key) end, C.sel)
      else
        f:field(fx, y, fw, fd.text, e.cursor, e.focus == key, function(pl, pos) actions.viewFocus(pl, key, pos) end)
      end
      y = y + 1
    end
  end
  return y
end

local function preview(f, pv, y, nx, fx, fw)
  f:text(nx, y, "Now", C.accent)
  if pv.error then
    f:text(fx, y, Gui.fit(pv.error, fw), C.bad)
    return
  end
  local color = frame.levelColor(pv.level, C.text)
  local text = ((pv.dots or pv.status) and pv.text == "–") and "" or pv.text or "–"   -- dots alone: no "–"
  f:text(fx, y, Gui.fit(text, 16), color)
  if pv.hidden then f:text(fx + 17, y, "(hidden now: Show when is false)", C.dim); return end
  if pv.dots or pv.status then
    local dots = pv.dots or {}
    if pv.status then dots = { { level = pv.status }, table.unpack(dots) } end
    f:dots(fx + 18, y, math.max(0, fw - 18), dots)
  elseif pv.frac then
    local bw = math.max(0, fw - 18)
    local filled = math.floor(math.max(0, math.min(1, pv.frac)) * bw + 0.5)
    if filled > 0 then f:text(fx + 18, y, string.rep(" ", filled), C.text, frame.levelColor(pv.level, C.info)) end
    if filled < bw then f:text(fx + 18 + filled, y, string.rep(" ", bw - filled), C.text, C.line) end
  end
end

function view.draw(f, e, actions)
  f:editorHeader(e.old and ("View: " .. e.old) or "New view",
    { { "SAVE", actions.viewSave }, { "CANCEL", actions.viewCancel, C.line } })
  local nx, fx = 2, 15
  local fw = f.w - fx - 1
  local gap = f.h >= 30 and 1 or 0                    -- spacer rows only when there's room (tier 2 has 25)
  local y = fields(f, e, actions, nx, fx, fw) + gap
  preview(f, e.preview or {}, y, nx, fx, fw)
  y = y + 1 + gap
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
    f:button(nx, y + gap, e.source == "edited" and "BACK TO lens-hub.cfg" or "DELETE VIEW", actions.viewDelete, C.line)
  end
  f:editorFooter(e)
end

return view
