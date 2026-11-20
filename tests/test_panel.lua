-- test_panel.lua: the panel page through lens-hub, on a 3 x 4 screen: tapping a panel opens it with its history as a
-- chart, low / average / high, an alert that started meanwhile, its query with what each part comes to and which
-- node sends it, its status rules (the first true one marked, the rest not tried), where it's shown; ADD TO MY HUD,
-- EDIT VIEW and back; `editors` hides EDIT VIEW. The pure part (lens.hub.inspect) on its own. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local inspect = require("lens.hub.inspect")
local files = require("lens.files")
local glassesMock = require("glasses")

---------------------------------------------------------------- inspect
do
  local parts = inspect.parts("sum(lumen_stored_eu) / sum(lumen_capacity_eu{node=\"a\"}) * 100 + sum(lumen_stored_eu)")
  check(#parts == 2 and parts[1] == "sum(lumen_stored_eu)" and parts[2] == 'sum(lumen_capacity_eu{node="a"})',
    "parts: each function call once, in order")
  check(#inspect.parts("lumen_fill_ratio > 0.5") == 0, "a bare selector has no parts")
  check(inspect.substitute("sum(a) / sum(b)", { ["sum(a)"] = "7.9G", ["sum(b)"] = "19.3G" }) == "7.9G / 19.3G",
    "substitute: each part by its value")
  local names = { "lumen_stored_eu", "lumen_stored", "lumen_capacity_eu" }
  local found = inspect.metrics("sum(lumen_capacity_eu) - sum(lumen_stored_eu)", names)
  check(#found == 2 and found[1] == "lumen_capacity_eu" and found[2] == "lumen_stored_eu",
    "metrics: whole names only, in the order the query uses them")
  local s = inspect.stats({ 1, false, 3, 5 })
  check(s.low == 1 and s.high == 5 and s.average == 3 and s.last == 5 and s.n == 3, "stats skip missing samples")
  check(inspect.stats({ false }) == nil, "no numbers: no stats")
end

---------------------------------------------------------------- through lens-hub
-- A power room that drains from 50% (19.3G capacity), with 3h 12m left after t = 60 and a fault from t = 90.
local CAP = 19.3e9
local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m, now)
  m:beginCycle()
  m:gauge("lumen_stored_eu", "stored", "EU"):set(CAP * math.max(0.3, 0.5 - now / 10000))
  m:gauge("lumen_capacity_eu", "capacity", "EU"):set(CAP)
  m:gauge("lumen_empty_seconds", "until empty", "s"):set(now >= 60 and 11520 or 30000)
  m:gauge("lumen_net_eut", "net", "EU/t"):set(-34300)
  if now >= 90 then m:alert("reactor:N-3", "bad", "Reactor N-3: fault signal") end
end }

local CFG = [[return { timezone = 0, panels = {
  { label = "Power", value = "sum(lumen_stored_eu) / sum(lumen_capacity_eu)", format = "percent", status = {
    { "bad", "$value < 0.1" },
    { "warn", "min(lumen_empty_seconds) < 14400" },
    { "good", "sum(lumen_net_eut) > 0" },
  } },
} }]]

local G = glassesMock.new()
M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
local seen = {}
local ok, err, dir = R.run{ cfg = CFG, agents = { power }, keyboard = true, terminals = { gl000000 = G },
  script = function(t)
  if t < 200 then return nil end
  if not seen.glasses then seen.glasses = true; return { "glasses_on", "gl000000", "Aaron", 854, 480 } end
  if not seen.tapped then seen.tapped = true; return R.tap("Power", "Aaron", 3) end
  if not seen.page then
    seen.page = true
    seen.header = M.find("Panel: Power", 1) and M.find(" EDIT VIEW ", 1) and M.find("LAST 3 MINUTES", 4)
      and M.find("one sample every 10 s", 4)
    seen.chart = M.find("▁", 6) or M.find("▇", 6)
    seen.alert = M.find("▲", 6) and M.find("Reactor N-3: fault signal", 6)
    seen.stats = M.find("low ", 10) and M.find("average ", 10) and M.find("high ", 10)
    seen.query = M.find("QUERY", 10) and M.find("sum(lumen_stored_eu) / sum(lumen_capacity_eu)", 10)
      and M.find("G / 19.3G = 0.4", 10) and M.find("from power-room", 10)
    seen.status = M.find("STATUS", 10) and M.find("▶", 10) and M.find("Yellow: rule 2 is the first true one.", 10)
      and M.find("not tried", 10)
    local _, y = M.find("▶", 10)
    seen.marked = y and M.row(y):find("min(lumen_empty_seconds)", 1, true) and M.row(y):find("yes", 1, true)
    seen.shown = M.find("Dashboard: Main", 10) and not M.find("HUD: Aaron", 10)
    H.screen("panel-portrait")
    return R.tap("ADD TO MY HUD", "Aaron", 10)
  end
  if not seen.added then
    seen.added = true
    seen.inHud = M.find("HUD: Aaron (main)", 10) ~= nil
    return R.tap(" EDIT VIEW ", "Aaron", 1)
  end
  if not seen.editing then
    seen.editing = true
    seen.viewEditor = M.find("View: Power", 1) ~= nil
    return R.tap("CANCEL", "Aaron", 1)
  end
  if not seen.backed then
    seen.backed = true
    seen.back = M.find("Panel: Power", 1) ~= nil
    return R.tap("DONE", "Aaron", 1)
  end
  seen.dash = M.find("Tap an alert to acknowledge it, a panel for more.", 50) ~= nil
  return "stop"
end }
M.aspect = nil
M.resize(160, 50)
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.header, "tapping a panel opens its page: name, EDIT VIEW, how long its history is")
check(seen.chart, "its history as a chart")
check(seen.alert, "an alert that started meanwhile, under the chart")
check(seen.stats, "low, average and high")
check(seen.query, "its query, what each part comes to, and which node sends it")
check(seen.status and seen.marked, "its status rules: the first true one marked, the rest not tried")
check(seen.shown, "where it's shown")
check(seen.inHud, "ADD TO MY HUD puts it in the player's HUD")
local saved = files.loadTable(dir .. "/lens-board.cfg")
local found = false
for _, p in ipairs(saved and saved.huds and saved.huds.Aaron and saved.huds.Aaron.presets or {}) do
  for _, b in ipairs(p.blocks or {}) do
    for _, el in ipairs(b.elements or {}) do if el.view == "Power" and el.kind == "bar" then found = true end end
  end
end
check(found, "as a bar (a percent), saved in lens-board.cfg")
check(seen.viewEditor and seen.back, "EDIT VIEW opens the view editor; CANCEL comes back to the panel")
check(seen.dash, "DONE: the dashboard, whose footer says panels can be tapped")

-- Only editors may change views.
seen = {}
ok = R.run{ cfg = CFG:gsub("^return {", 'return { editors = { "Aaron" },'), dir = "editors", agents = { power },
  script = function(t)
  if t < 30 then return nil end
  if not seen.tapped then seen.tapped = true; return R.tap("Power", "Bob", 3) end
  seen.noEdit = M.find("Panel: Power", 1) and not M.find("EDIT VIEW", 1) and not M.find("ADD TO MY HUD", 3)
  return "stop"
end }
check(ok and seen.noEdit, "with editors set, others see the page without EDIT VIEW (and no HUD without glasses)")

H.done()
