--[[ lens.hub.editors.log: the LOG page: alerts happening now, then the ones that have ended (the hub's
  alerts:history, newest first: kept in memory, so a restart starts over). Read-only. Drawn by
  lens.hub.pages.log. The editor interface: lens.hub.editors.hud.

  State: { kind = "log", player, page = 1.. }
  Actions: log(player) opens it; logDone, logPage(-1 | 1).
]]

local E = {}

function E.actions(app, a, mine)
  a.log = function(player) app:open("log", player, { page = 1 }) end
  a.logDone = mine(function() app:close() end)
  a.logPage = mine(function(_, dir) app.editing.page = math.max(1, app.editing.page + dir) end)
end

function E.model(app, e, now)
  return { now = now, active = app.hub.alerts:list(), past = app.hub.alerts:history(), page = e.page }
end

return E
