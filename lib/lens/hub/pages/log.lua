--[[ lens.hub.pages.log: the LOG page (lens.hub.editors.log): a timeline of the last 12 or 24 hours (a band per
  node, colored by its worst alert, │ where it restarted), then alerts happening now, then the kept log
  (lens.hub.logbook), newest first: alerts that ended, with when they started and how long they lasted, and when
  lens-hub started and stopped, and nodes that restarted.

  log.draw(f, e, actions)   e: { time, tz, active = alerts:list() with since in real seconds, past = logbook
                            entries (an alert's ackedBy: who acknowledged it), page, hours, timeline =
                            lens.hub.timeline.bands, ticks, player, error, closesIn }. The band starts at
                            column 15. Times read as frame.when. Rows that don't fit go on further pages (◀ ▶);
                            the timeline stays on each.
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
  if a.ackedBy then when = when .. " · ✓ " .. a.ackedBy end
  local label = a.text .. ((a.node and not a.text:find(a.node, 1, true)) and ("  · " .. a.node) or "")
  line(f, y, label, when, past and C.dim or C.text)
end

local function eventRow(f, y, ev, e)
  if ev.kind == "restart" then
    f:text(2, y, Gui.fit(" NODE", 6), C.accent)
    line(f, y, tostring(ev.node) .. " restarted", frame.when(ev.at, e.time, e.tz), C.text)
    return
  end
  f:text(2, y, Gui.fit(" LENS", 6), C.accent)
  line(f, y, EVENTS[ev.kind] or ev.kind, frame.when(ev.at, e.time, e.tz), C.dim)
end

local BAND = 15

-- The timeline from row y -> the row after it.
local function timelineAt(f, y, e)
  local tl = e.timeline
  if not tl then return y end
  local cols = f.w - BAND
  f:heading(2, y, "TIMELINE", 8)
  local about = ("last %d hours, a column is %d minutes"):format(e.hours or 12, math.floor(tl.step / 60 + 0.5))
  f:text(12, y, Gui.fit(about, f.w - 12), C.dim)
  y = y + 1
  if #tl.rows == 0 then
    f:text(2, y, Gui.fit(("No alerts in the last %d hours."):format(e.hours or 12), f.w - 2), C.dim)
    return y + 1
  end
  for _, t in ipairs(e.ticks or {}) do f:text(BAND - 1 + t[1], y, t[2], C.dim) end
  y = y + 1
  for _, r in ipairs(tl.rows) do
    f:text(2, y, Gui.fit(r.node, BAND - 3), C.dim)
    -- Runs of one color as one segment.
    local c = 1
    while c <= cols do
      local level, mark = r.cells[c], r.marks[c]
      local stop = c
      if not mark then
        while stop < cols and r.cells[stop + 1] == level and not r.marks[stop + 1] do stop = stop + 1 end
      end
      local bg = level == "bad" and C.bad or level == "warn" and C.warn or C.panel
      f:text(BAND - 1 + c, y, mark and "│" or string.rep(" ", stop - c + 1), C.text, bg)
      c = stop + 1
    end
    y = y + 1
  end
  if tl.more > 0 then f:text(2, y, ("+%d more nodes"):format(tl.more), C.dim) end
  f:text(BAND, y, " WARN ", C.bg, C.warn)        -- the legend, under the bands
  f:text(BAND + 7, y, " BAD ", C.bg, C.bad)
  f:text(BAND + 13, y, "│ restart", C.dim)
  return y + 1
end

local function hourButton(actions, hours, shown)
  return { ("%d H"):format(hours), function(p) actions.logHours(p, hours) end, shown == hours and C.btnOn or C.btn }
end

function log.draw(f, e, actions)
  f:editorHeader("Alert log", { hourButton(actions, 12, e.hours), hourButton(actions, 24, e.hours),
    { "DONE", actions.logDone } })
  local top = timelineAt(f, 3, e) + 1
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

  local per = math.max(1, f.h - 1 - top)
  local pages = math.max(1, (#lines + per - 1) // per)
  local page = math.min(e.page or 1, pages)
  local y = top
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
