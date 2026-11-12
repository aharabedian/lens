--[[ lens.hub.editors.data: the DATA page: every metric (store:metrics), one metric's series, a query built by
  tapping label values and a function (lens.hub.explore), then made into a view for the dashboard or the
  player's HUD (lens.hub.editors.view). Drawn by lens.hub.pages.data. The editor interface:
  lens.hub.editors.hud.

  State: { kind = "data", player, metric = name | nil, filters = { [label] = value }, fn, page }
  Actions: data(player) opens it; dataDone, dataPick(name, type), dataBack, dataPage(-1 | 1),
  dataFilter(label, value | nil), dataFn(fn), dataPanel (cfg.editors, when set), dataHud.
]]

local explore = require("lens.hub.explore")
local format = require("lens.hub.format")
local query = require("lens.hub.query")
local view = require("lens.hub.editors.view")

local E = {}

local function metric(app, name, now)
  for _, m in ipairs(app.hub:metrics(now)) do if m.name == name then return m end end
end

-- What a view made from the query starts with: the query, a label, and the unit the function leaves.
local function draft(app)
  local e = app.editing
  local m = metric(app, e.metric, app.now)
  local unit = m and m.unit
  if unit and e.fn == "rate" then unit = unit .. "/s" elseif e.fn == "count" then unit = nil end
  return { label = explore.suggestLabel(e.metric, e.filters), value = explore.query(e.metric, e.filters, e.fn), unit = unit }
end

-- The state to come back to after the view editor.
local function keep(e) return { kind = "data", metric = e.metric, filters = e.filters, fn = e.fn, page = e.page } end

function E.actions(app, a, mine)
  a.data = function(player) app:open("data", player, { filters = {}, fn = "sum", page = 1 }) end
  a.dataDone = mine(function() app:close() end)
  a.dataPick = mine(function(_, name, kind)
    local e = app.editing
    e.metric, e.filters, e.fn = name, {}, kind == "counter" and "rate" or "sum"
  end)
  a.dataBack = mine(function() app.editing.metric = nil end)
  a.dataPage = mine(function(_, dir) app.editing.page = math.max(1, app.editing.page + dir) end)
  a.dataFilter = mine(function(_, label, value)
    local f = app.editing.filters
    if value == nil or f[label] == value then f[label] = nil else f[label] = value end
  end)
  a.dataFn = mine(function(_, fn) app.editing.fn = fn end)
  a.dataPanel = mine(function(player)
    if not app:mayEdit(player) then
      return nil, ("Only %s can add to the dashboard."):format(table.concat(app.cfg.editors, ", "))
    end
    view.start(app, player, draft(app), keep(app.editing), "dash")
  end)
  a.dataHud = mine(function(player)
    if not app.huds then return nil, "No Glasses Terminal: there's no HUD to add to." end
    view.start(app, player, draft(app), keep(app.editing), "hud")
  end)
end

function E.model(app, e, now)
  local m = { metrics = app.hub:metrics(now), page = e.page, editors = app.cfg.editors,
    canPanel = app:mayEdit(e.player), canHud = app.huds ~= nil }
  m.metric = e.metric and metric(app, e.metric, now)
  if not m.metric then return m end
  local all = app.hub:lookup(now)(e.metric)
  local rows = {}
  for _, s in ipairs(all) do
    if explore.matches(s, e.filters) then
      rows[#rows + 1] = { labels = explore.labelText(s.labels), text = format.number(s.value),
        rate = s.rate and (format.number(s.rate) .. "/s") or nil }
    end
  end
  table.sort(rows, function(x, y) return x.labels < y.labels end)
  m.series, m.labels, m.fn, m.funcs = rows, explore.labels(all, e.filters), e.fn, explore.FUNCS
  m.query = explore.query(e.metric, e.filters, e.fn)
  local v = query.compile(m.query)(app.hub:lookup(now))   -- not hub:query: that caches every text it sees
  local unit = (m.metric.unit and e.fn ~= "count") and (" " .. m.metric.unit) or ""
  m.value = v and (format.number(v) .. unit .. (e.fn == "rate" and "/s" or "")) or "– (no data)"
  return m
end

return E
