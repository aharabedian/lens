--[[ lens.hub.editors.panel: the panel page, opened by tapping a panel on the dashboard: its history as a chart,
  low / average / high, the alerts that started meanwhile, its query and what each part comes to, its status rules
  (which one set the dot), where it's shown, EDIT VIEW and ADD TO MY HUD. Drawn by lens.hub.pages.panel. The
  editor interface: lens.hub.editors.hud.

  State: { kind = "panel", player, label }
  Actions: panel(player, label) opens it; panelDone, panelEdit (the view editor, back here; cfg.editors),
           panelHud (the view at the end of the player's HUD's first block), panelAlert (an alert from its first
           bad or warn status rule, else its value above 0: lens.hub.editors.rule; cfg.editors).
  Model: { label, missing = bool (the view is gone), shown = app:evaluate's row (text, level, status...),
           history = { number | false... } (one every cfg.sample seconds, oldest first), sample, time (real),
           tz, stats = lens.hub.inspect.stats as text { low, average, high, last },
           alerts = { { since (real), level, text, node }... } (started within the history, oldest first),
           query = { text, parts = text | nil ("= 7.9G / 19.3G"), value, nodes = { name... } },
           of = { text, value } | nil, values = { { name, text, value }... } | nil,
           status = { { level, text, result = "yes" | "no" | "no data" | "not tried", first = bool }... } | nil,
           shownOn = { pages = { name... }, huds = { "Aaron (main)"... } }, canEdit, canHud }
]]

local format = require("lens.hub.format")
local inspect = require("lens.hub.inspect")
local view = require("lens.hub.editors.view")
local ruleEditor = require("lens.hub.editors.rule")

local E = {}

-- A value as the view writes it, without its template or `of` (for low, high and the chart's scale).
local function plain(v)
  local copy = {}
  for k, x in pairs(v) do copy[k] = x end
  copy.text, copy.values, copy.of, copy.status, copy.dots = nil, nil, nil, nil, nil
  return function(x) return (format.view(copy, x)) end
end

local function number(x) return x == nil and "– (no data)" or format.number(x) end

-- Where the view is used: dashboard pages, and players' HUDs (any preset).
local function shownOn(app, label)
  local out = { pages = {}, huds = {} }
  for i, pg in ipairs(app.board:pages()) do
    if app.board:onDashboard(label, i) then out.pages[#out.pages + 1] = pg.name end
  end
  local function uses(s)
    for _, b in ipairs(type(s) == "table" and type(s.blocks) == "table" and s.blocks or {}) do
      for _, el in ipairs(type(b.elements) == "table" and b.elements or {}) do
        if type(el) == "table" and el.view == label then return true end
      end
    end
    return false
  end
  local names = {}
  for name in pairs(app.board:players()) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local r = app.board:players()[name]
    local which = {}
    for _, p in ipairs(type(r) == "table" and type(r.presets) == "table" and r.presets or {}) do
      if uses(p) then which[#which + 1] = tostring(p.name) end
    end
    if uses(r) then which[#which + 1] = "main" end
    if #which > 0 then out.huds[#out.huds + 1] = ("%s (%s)"):format(name, table.concat(which, ", ")) end
  end
  return out
end

function E.actions(app, a, mine)
  a.panel = function(player, label) app:open("panel", player, { label = label }) end
  a.panelDone = mine(function() app:close() end)
  a.panelEdit = mine(function(player)
    if not app:mayEdit(player) then
      return nil, ("Only %s can change views."):format(table.concat(app.cfg.editors, ", "))
    end
    local v = app.board:view(app.editing.label)
    if not v then return nil, "That view is gone." end
    view.start(app, player, v, { kind = "panel", label = app.editing.label })
  end)
  a.panelAlert = mine(function(player)
    if not app:mayEdit(player) then
      return nil, ("Only %s can make alerts."):format(table.concat(app.cfg.editors, ", "))
    end
    local v = app.board:view(app.editing.label)
    if not v then return nil, "That view is gone." end
    local r = { text = v.label, level = "warn" }
    for _, s in ipairs(v.status or {}) do
      if s[1] == "bad" or s[1] == "warn" then
        r.when, r.level = format.expand(s[2], v.value), s[1]
        break
      end
    end
    r.when = r.when or (v.value and ("(" .. v.value .. ") > 0")) or ""
    ruleEditor.start(app, player, r, { kind = "panel", label = app.editing.label })
  end)
  a.panelHud = mine(function(player)
    if not app.huds then return nil, "No Glasses Terminal: there's no HUD to add to." end
    local v = app.board:view(app.editing.label)
    if not v then return nil, "That view is gone." end
    local kind = (v.of or v.max or v.format == "percent") and "bar" or "text"
    return app.huds:change(player, function(s)
      local els = s.blocks[1].elements
      els[#els + 1] = { kind = kind, view = v.label }
    end)
  end)
end

function E.model(app, e, now)
  local v = app.board:view(e.label)
  local m = { label = e.label, canEdit = app:mayEdit(e.player), canHud = app.huds ~= nil, sample = app.cfg.sample,
    tz = app.cfg.timezone, time = app:real(now) }
  if not v then
    m.missing = true
    return m
  end
  m.shown = app:evaluate({ v }, nil, now)[1]
  m.history = app.history[e.label] or {}
  local fmt = plain(v)
  local st = inspect.stats(m.history)
  if st then m.stats = { low = fmt(st.low), average = fmt(st.average), high = fmt(st.high), last = fmt(st.last) } end
  -- Alerts that started while the history was kept.
  local from = m.time - #m.history * app.cfg.sample
  local list = {}
  for _, x in ipairs(app.logbook:list()) do
    if x.kind == "alert" and x.since >= from then list[#list + 1] = x end
  end
  for _, x in ipairs(app.hub.alerts:list()) do
    local since = m.time - (now - x.since)
    if since >= from then list[#list + 1] = { since = since, level = x.level, text = x.text, node = x.node } end
  end
  table.sort(list, function(x, y) return x.since < y.since end)
  m.alerts = list
  local function value(q) return (app.hub:query(q, now)) end
  if v.value then
    local parts, texts = inspect.parts(v.value), {}
    for _, p in ipairs(parts) do texts[p] = number(value(p)) end
    local whole = number(value(v.value))
    local names = {}
    for _, x in ipairs(app.hub:metrics(now)) do names[#names + 1] = x.name end
    local nodes, seenNode = {}, {}
    for _, name in ipairs(inspect.metrics(v.value, names)) do
      for _, x in ipairs(app.hub:metrics(now)) do
        if x.name == name then
          for _, n in ipairs(x.nodes) do
            if not seenNode[n] then seenNode[n] = true; nodes[#nodes + 1] = n end
          end
        end
      end
    end
    local substituted = #parts > 0 and inspect.substitute(v.value, texts) or nil
    if substituted == whole then substituted = nil end
    m.query = { text = v.value, parts = substituted, value = whole, nodes = nodes }
  end
  if v.of then m.of = { text = v.of, value = number(value(v.of)) } end
  if v.values then
    m.values = {}
    local keys = {}
    for k in pairs(v.values) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do m.values[#m.values + 1] = { name = k, text = v.values[k], value = number(value(v.values[k])) } end
  end
  if v.status then
    m.status = {}
    local found = false
    for _, rule in ipairs(v.status) do
      local row = { level = rule[1], text = rule[2] }
      if found then
        row.result = "not tried"
      else
        local w = value(format.expand(rule[2], v.value))
        if w == nil then row.result = "no data"
        elseif w ~= 0 then row.result, row.first, found = "yes", true, true
        else row.result = "no" end
      end
      m.status[#m.status + 1] = row
    end
  end
  m.shownOn = shownOn(app, e.label)
  return m
end

return E
