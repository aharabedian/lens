--[[ lens.hub.editors.log: the LOG page: alerts happening now, then the kept log (lens.hub.logbook, in
  lens-log.cfg, so a restart keeps it), newest first. Read-only. Drawn by lens.hub.pages.log. The editor
  interface: lens.hub.editors.hud.

  State: { kind = "log", player, page = 1.., hours = 12 | 24 }
  Actions: log(player) opens it; logDone, logPage(-1 | 1), logHours(12 | 24).
  Model: { time (real seconds), tz (cfg.timezone), active (alerts:list(), since in real seconds), past
           (logbook:list()), page, hours, timeline = lens.hub.timeline.bands over the screen's width less 15
           columns, ticks = timeline.ticks }
]]

local timeline = require("lens.hub.timeline")

local E = {}

function E.actions(app, a, mine)
  a.log = function(player) app:open("log", player, { page = 1, hours = 12 }) end
  a.logHours = mine(function(_, hours) app.editing.hours = hours end)
  a.logDone = mine(function() app:close() end)
  a.logPage = mine(function(_, dir) app.editing.page = math.max(1, app.editing.page + dir) end)
end

function E.model(app, e, now)
  local time = app:real(now)
  local active = {}
  for _, a in ipairs(app.hub.alerts:list()) do
    local copy = {}
    for k, v in pairs(a) do copy[k] = v end
    copy.since = time - (now - a.since)
    active[#active + 1] = copy
  end
  local past = app.logbook:list()
  local all = {}
  for _, x in ipairs(past) do all[#all + 1] = x end
  for _, x in ipairs(active) do all[#all + 1] = x end
  local span, cols = e.hours * 3600, math.max(10, app.dash.w - 15)
  return { time = time, tz = app.cfg.timezone, active = active, past = past, page = e.page, hours = e.hours,
    timeline = timeline.bands(all, time, span, cols, app.dash.h >= 40 and 8 or 4),
    ticks = timeline.ticks(time, span, cols, app.cfg.timezone) }
end

return E
