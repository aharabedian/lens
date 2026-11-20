--[[ lens.hub.editors.node: the node page, opened by tapping a node on the dashboard: its health, role and version,
  how often it reports and when it last did, its distance, snapshots whole and cut short, its alerts, its last 24
  hours (a timeline band), its metrics, and the views that read them. FORGET drops a node that stopped. Drawn by
  lens.hub.pages.node. The editor interface: lens.hub.editors.hud.

  State: { kind = "node", player, name }
  Actions: node(player, name) opens it; nodeDone, nodeForget (a stale node; cfg.editors).
  Model: { name, found = bool, health, role, version, boot, interval, ago (seconds since it last reported), stale,
           traffic = core:traffic, alerts = { alert with since in real seconds }, time, tz,
           band = lens.hub.timeline row | nil, step, ticks (24 hours over the screen's width less 15),
           metrics = store:nodeMetrics, usedBy = { label... } (views reading its metrics), canForget }
]]

local timeline = require("lens.hub.timeline")
local inspect = require("lens.hub.inspect")

local E = {}

function E.actions(app, a, mine)
  a.node = function(player, name) app:open("node", player, { name = name }) end
  a.nodeDone = mine(function() app:close() end)
  a.nodeForget = mine(function(player)
    if not app:mayEdit(player) then
      return nil, ("Only %s can forget nodes."):format(table.concat(app.cfg.editors, ", "))
    end
    app.hub:forget(app.editing.name)
    app:close()
  end)
end

-- Labels of views whose queries read any of these metrics, or name the node.
local function usedBy(app, name, metricNames)
  local out = {}
  for _, v in ipairs(app.board:views()) do
    local texts = { v.value, v.of, v.when, v.dots }
    for _, q in pairs(v.values or {}) do texts[#texts + 1] = q end
    for _, r in ipairs(v.status or {}) do texts[#texts + 1] = r[2] end
    local hit = false
    for _, t in pairs(texts) do
      if type(t) == "string" and (#inspect.metrics(t, metricNames) > 0 or t:find('"' .. name .. '"', 1, true)) then
        hit = true
      end
    end
    if hit then out[#out + 1] = v.label end
  end
  return out
end

function E.model(app, e, now)
  local m = { name = e.name, time = app:real(now), tz = app.cfg.timezone, canForget = app:mayEdit(e.player) }
  local n
  for _, x in ipairs(app.hub:nodes(now)) do if x.name == e.name then n = x end end
  if not n then return m end
  m.found = true
  m.health, m.role, m.version, m.boot, m.interval, m.stale = n.health, n.role, n.version, n.boot, n.interval, n.stale
  m.ago = n.lastSeen and now - n.lastSeen or nil
  m.traffic = app.hub:traffic(e.name)
  m.alerts = {}
  for _, a in ipairs(app.hub.alerts:list()) do
    if a.node == e.name then
      local copy = {}
      for k, v in pairs(a) do copy[k] = v end
      copy.since = m.time - (now - a.since)
      m.alerts[#m.alerts + 1] = copy
    end
  end
  local entries = {}
  for _, x in ipairs(app.logbook:list()) do if x.node == e.name then entries[#entries + 1] = x end end
  for _, x in ipairs(m.alerts) do entries[#entries + 1] = x end
  local cols = math.max(10, app.dash.w - 15)
  local b = timeline.bands(entries, m.time, 86400, cols, 1)
  m.band, m.step = b.rows[1], b.step
  m.ticks = timeline.ticks(m.time, 86400, cols, app.cfg.timezone)
  m.metrics = app.hub.store:nodeMetrics(e.name)
  local names = {}
  for _, x in ipairs(m.metrics) do names[#names + 1] = x.name end
  m.usedBy = usedBy(app, e.name, names)
  return m
end

return E
