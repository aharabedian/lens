--[[ lens.hub.pages.log: the LOG page (lens.hub.editors.log): alerts happening now, then the kept log
  (lens.hub.logbook), newest first: alerts that ended, with when they started and how long they lasted, and when
  lens-hub started and stopped.

  log.draw(f, e, actions)   e: { time, tz, active = alerts:list() with since in real seconds, past = logbook
                            entries, page, player, error, closesIn }. Times read as frame.when. Rows that don't
                            fit go on further pages (◀ ▶).
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local log = {}

local C = frame.C
local EVENTS = { start = "lens-hub started", stop = "lens-hub stopped" }

local function tagFor(f, y, level, past)
  local tag = Gui.fit(level == "bad" and " BAD" or " WARN", 6)
  if past then
    f:text(2, y, tag, level == "bad" and C.bad or C.warn)
  else
    f:text(2, y, tag, C.bg, level == "bad" and C.bad or C.warn)
  end
end

-- The label on the left and `when` on the right of row y.
local function line(f, y, label, when, fg)
  f:text(9, y, Gui.fit(label, f.w - 10 - Gui.len(when) - 2), fg)
  f:text(f.w - Gui.len(when), y, when, C.dim)
end

local function alertRow(f, y, a, e, past)
  tagFor(f, y, a.level, past)
  local when
  if past then
    when = ("%s, lasted %s"):format(frame.when(a.since, e.time, e.tz), frame.ago(a.at - a.since))
  else
    when = "for " .. frame.ago(e.time - a.since)
  end
  local label = a.text .. ((a.node and not a.text:find(a.node, 1, true)) and ("  · " .. a.node) or "")
  line(f, y, label, when, past and C.dim or C.text)
end

local function eventRow(f, y, ev, e)
  f:text(2, y, Gui.fit(" LENS", 6), C.accent)
  line(f, y, EVENTS[ev.kind] or ev.kind, frame.when(ev.at, e.time, e.tz), C.dim)
end

function log.draw(f, e, actions)
  f:editorHeader("Alert log", { { "DONE", actions.logDone } })
  -- Everything as one list of lines (headings and rows), then shown a page at a time.
  local lines = { { heading = ("NOW (%d)"):format(#e.active) } }
  if #e.active == 0 then lines[#lines + 1] = { note = "All quiet." } end
  for _, a in ipairs(e.active) do lines[#lines + 1] = { alert = a } end
  lines[#lines + 1] = { blank = true }
  lines[#lines + 1] = { heading = ("EARLIER (%d)"):format(#e.past), note = "kept in lens-log.cfg" }
  if #e.past == 0 then lines[#lines + 1] = { note = "Nothing yet." } end
  for _, a in ipairs(e.past) do
    if a.kind == "alert" then lines[#lines + 1] = { alert = a, past = true }
    else lines[#lines + 1] = { event = a } end
  end

  local per = math.max(1, f.h - 5)
  local pages = math.max(1, (#lines + per - 1) // per)
  local page = math.min(e.page or 1, pages)
  local y = 3
  for i = (page - 1) * per + 1, math.min(#lines, page * per) do
    local l = lines[i]
    if l.heading then
      f:heading(2, y, l.heading, Gui.len(l.heading))
      if l.note then f:text(4 + Gui.len(l.heading), y, Gui.fit(l.note, f.w - 4 - Gui.len(l.heading)), C.dim) end
    elseif l.note then f:text(2, y, Gui.fit(l.note, f.w - 2), C.dim)
    elseif l.alert then alertRow(f, y, l.alert, e, l.past)
    elseif l.event then eventRow(f, y, l.event, e) end
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
