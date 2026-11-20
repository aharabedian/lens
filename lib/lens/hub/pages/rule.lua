--[[ lens.hub.pages.rule: alerts made on the screen (lens.hub.editors.rule). The list: the ones made here, each with
  its level, text, query, how long it must stay true and whether it's firing, true or false now (EDIT, + NEW), then
  lens-hub.cfg's, read-only. The form: Text, When, For (s) as fields, the level as a chip, and NOW.

  rule.draw(f, e, actions)   e: the editor's model (its header comment), plus player, error, closesIn
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local rule = {}

local C = frame.C
local STATE_COLOR = { firing = C.bad, ["true"] = C.warn, ["false"] = C.dim, ["no data"] = C.dim, empty = C.dim,
  error = C.bad }

local function tag(f, x, y, level)
  f:text(x, y, Gui.fit(level == "bad" and " BAD" or " WARN", 6), C.bg, level == "bad" and C.bad or C.warn)
end

-- A rule's two rows -> the row after.
local function row(f, r, y, actions, editable)
  tag(f, 2, y, r.level)
  local right = editable and 8 or 0
  local st = r.state == "firing" and "firing" or (r.state .. " now")
  f:text(9, y, Gui.fit(r.text, f.w - 9 - right - Gui.len(st) - 2), C.text)
  f:text(f.w - right - Gui.len(st), y, st, r.state == "firing" and (r.level == "bad" and C.bad or C.warn)
    or STATE_COLOR[r.state] or C.dim)
  if editable then
    local id = r.id
    f:button(f.w - 6, y, "EDIT", function(p) actions.ruleEdit(p, id) end)
  end
  local hold = r.hold > 0 and ("  for %ds"):format(r.hold) or ""
  f:text(9, y + 1, Gui.fit(r.when .. hold, f.w - 9), C.dim)
  return y + 2
end

local function list(f, e, actions)
  f:editorHeader("Alerts", { { "+ NEW", actions.ruleNew }, { "DONE", actions.ruleDone } })
  local y, last = 3, f.h - 2
  f:heading(2, y, ("MADE HERE (%d)"):format(#e.screen), f.w - 2)
  y = y + 1
  if #e.screen == 0 then
    f:text(2, y, Gui.fit("None yet: + NEW, or SAVE AS ALERT on DATA or a panel's page.", f.w - 2), C.dim)
    y = y + 1
  end
  for i, r in ipairs(e.screen) do
    if y + 1 > last then f:text(2, y, ("+%d more"):format(#e.screen - i + 1), C.dim); y = y + 1; break end
    y = row(f, r, y, actions, true)
  end
  y = y + 1
  if #e.config > 0 and y + 2 <= last then
    local heading = ("FROM lens-hub.cfg (%d)"):format(#e.config)
    f:heading(2, y, heading, Gui.len(heading))
    f:text(4 + Gui.len(heading), y, Gui.fit("change these there", f.w - 4 - Gui.len(heading)), C.dim)
    y = y + 1
    for i, r in ipairs(e.config) do
      if y + 1 > last then f:text(2, y, ("+%d more"):format(#e.config - i + 1), C.dim); break end
      y = row(f, r, y, actions, false)
    end
  end
  f:editorFooter(e)
end

local function form(f, e, actions)
  f:editorHeader(e.old and ("Alert: " .. e.old) or "New alert",
    { { "SAVE", actions.ruleSave }, { "CANCEL", actions.ruleCancel, C.line } })
  local nx, fx = 2, 12
  local fw = f.w - fx - 1
  local y = 3
  for _, fd in ipairs(e.fields) do
    f:text(nx, y, Gui.fit(fd.name, fx - nx - 1), e.focus == fd.key and C.accent or C.dim)
    local key = fd.key
    f:field(fx, y, fw, fd.text, e.cursor, e.focus == key, function(p, pos) actions.ruleFocus(p, key, pos) end)
    y = y + 2
  end
  f:text(nx, y, "Level", C.dim)
  f:button(fx, y, e.level == "bad" and "BAD" or "WARN", actions.ruleLevel, e.level == "bad" and C.bad or C.warn)
  f:text(fx + 8, y, Gui.fit("tap to switch", f.w - fx - 8), C.dim)
  y = y + 2
  f:heading(nx, y, "NOW", 3)
  f:text(fx, y, Gui.fit(e.now.text, fw), STATE_COLOR[e.now.state] or C.text)
  y = y + 2
  local help = "It's raised under the hub's name when When is true (not 0) for For seconds. Missing data never fires."
  for _, l in ipairs(frame.wrap(help, f.w - 2)) do f:text(nx, y, l, C.dim); y = y + 1 end
  if e.keyboard then
    f:text(nx, y, Gui.fit("Tap a field and type. Enter: the next field. Insert pastes your clipboard.", f.w - 2), C.dim)
  else
    f:text(nx, y, Gui.fit("No keyboard on this screen: attach one to type into the fields.", f.w - 2), C.warn)
  end
  y = y + 2
  if e.old then f:button(nx, y, "DELETE ALERT", actions.ruleDelete, C.line) end
  f:editorFooter(e)
end

function rule.draw(f, e, actions)
  if e.list then list(f, e, actions) else form(f, e, actions) end
end

return rule
