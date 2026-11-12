--[[ lens.hub.pages.log: the LOG page (lens.hub.editors.log): alerts happening now, then the ones that have
  ended, newest first, with when they started and how long they lasted.

  log.draw(f, e, actions)   e: { now, active = alerts:list(), past = alerts:history(), page, player, error,
                            closesIn }. Rows that don't fit go on further pages (◀ ▶).
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local log = {}

local C = frame.C

local function row(f, y, a, now, past)
  local tag = Gui.fit(a.level == "bad" and " BAD" or " WARN", 6)
  if past then
    f:text(2, y, tag, a.level == "bad" and C.bad or C.warn)
  else
    f:text(2, y, tag, C.bg, a.level == "bad" and C.bad or C.warn)
  end
  local when
  if past then
    when = ("%s ago, lasted %s"):format(frame.ago(now - a.ended), frame.ago(a.ended - a.since))
  else
    when = "for " .. frame.ago(now - a.since)
  end
  local label = a.text .. ((a.node and not a.text:find(a.node, 1, true)) and ("  · " .. a.node) or "")
  f:text(9, y, Gui.fit(label, f.w - 10 - Gui.len(when) - 2), past and C.dim or C.text)
  f:text(f.w - Gui.len(when), y, when, C.dim)
end

function log.draw(f, e, actions)
  f:editorHeader("Alert log", { { "DONE", actions.logDone } })
  -- Everything as one list of lines (headings and alerts), then shown a page at a time.
  local lines = { { heading = ("NOW (%d)"):format(#e.active) } }
  if #e.active == 0 then lines[#lines + 1] = { note = "All quiet." } end
  for _, a in ipairs(e.active) do lines[#lines + 1] = { alert = a } end
  lines[#lines + 1] = { blank = true }
  lines[#lines + 1] = { heading = ("EARLIER (%d)"):format(#e.past) }
  if #e.past == 0 then lines[#lines + 1] = { note = "Nothing has ended since the hub started." } end
  for _, a in ipairs(e.past) do lines[#lines + 1] = { alert = a, past = true } end

  local per = math.max(1, f.h - 5)
  local pages = math.max(1, (#lines + per - 1) // per)
  local page = math.min(e.page or 1, pages)
  local y = 3
  for i = (page - 1) * per + 1, math.min(#lines, page * per) do
    local l = lines[i]
    if l.heading then f:heading(2, y, l.heading, f.w - 2)
    elseif l.note then f:text(2, y, Gui.fit(l.note, f.w - 2), C.dim)
    elseif l.alert then row(f, y, l.alert, e.now, l.past) end
    y = y + 1
  end
  if pages > 1 then
    local py = f.h - 1
    if page > 1 then f:button(2, py, "◀", function(p) actions.logPage(p, -1) end) end
    f:text(7, py, ("page %d of %d"):format(page, pages), C.dim)
    if page < pages then f:button(21, py, "▶", function(p) actions.logPage(p, 1) end) end
  end
  f:editorFooter(e, "can page through this")
end

return log
