--[[ lens.hub.editors.log: the LOG page: alerts happening now, then the kept log (lens.hub.logbook, in
  lens-log.cfg, so a restart keeps it), newest first. Read-only. Drawn by lens.hub.pages.log. The editor
  interface: lens.hub.editors.hud.

  State: { kind = "log", player, page = 1.. }
  Actions: log(player) opens it; logDone, logPage(-1 | 1).
  Model: { time (real seconds), tz (cfg.timezone), active (alerts:list(), since in real seconds), past
           (logbook:list()), page }
]]

local E = {}

function E.actions(app, a, mine)
  a.log = function(player) app:open("log", player, { page = 1 }) end
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
  return { time = time, tz = app.cfg.timezone, active = active, past = app.logbook:list(), page = e.page }
end

return E
