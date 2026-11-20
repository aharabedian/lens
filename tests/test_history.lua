-- test_history.lua: the panels' last 24 hours (history = true). lens.hub.daily on its own: one value a 10-minute slot
-- (the average), gaps as false, at most 144, kept panels only, saved and read back, slots missed while the hub was off;
-- through lens-hub: 24 H on the panel page, lens-history.cfg, still there after a restart; off by default.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local daily = require("lens.hub.daily")
local files = require("lens.files")
local config = require("lens.hub.config")

check(config.check({}).history == false, "history is off by default")

---------------------------------------------------------------- on its own
do
  local path = H.TMP .. "/history.cfg"
  local d = daily.new(path)
  local t0 = 1795154400                         -- a slot boundary (06:00 UTC)
  d:add("Power", 10, t0 + 10)
  d:add("Power", 20, t0 + 300)
  check(#d:values("Power", t0 + 500) == 0 and not d.dirty, "the open slot isn't a value yet")
  d:add("Power", 40, t0 + 600)                  -- next slot: the first closes
  local v = d:values("Power", t0 + 700)
  check(#v == 1 and v[1] == 15 and d.dirty, "a slot closes with the average of its samples")
  d:add("Power", nil, t0 + 1200)
  d:add("Power", 50, t0 + 3000)                 -- slots 2..4 missed (no data, or nothing came)
  v = d:values("Power", t0 + 3001)
  check(#v == 5 and v[2] == 40 and v[3] == false and v[4] == false and v[5] == false, "no data and missed slots: false")
  check(d:save() and files.exists(path), "saved")
  local again = daily.new(path)
  v = again:values("Power", t0 + 3001)
  check(#v == 5 and v[1] == 15 and v[2] == 40, "read back")
  again:add("Power", 60, t0 + 4300)             -- after a restart: the slots it was off for are false
  v = again:values("Power", t0 + 4300)
  check(#v == 7 and v[6] == false, "slots missed while the hub was off: false")
  for i = 1, 200 do again:add("Power", i, t0 + 4300 + i * 600) end
  check(#again:values("Power", t0 + 4300 + 201 * 600) == 144, "at most 144 (24 hours)")
  again:add("Ore", 1, t0)
  again:keep({ Power = true })
  check(#again:values("Ore", t0 + 700) == 0, "keep: only panels still on the dashboard")
end

---------------------------------------------------------------- through lens-hub
local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m, now)
  m:beginCycle()
  m:gauge("lumen_fill_ratio", "f"):set(0.5 + 0.4 * math.sin(now / 300))
end }
local CFG = [[return { history = true, sample = 30, timezone = 0, panels = {
  { label = "Power", value = "lumen_fill_ratio", format = "percent" },
} }]]

M.setTime(0)
local seen = {}
local step = 0
local ok, err, dir = R.run{ cfg = CFG, dir = "hist", agents = { power }, script = function(t)
  if t < 1900 then return nil end
  step = step + 1
  if step == 1 then return R.tap("Power", "Aaron", 3) end
  if step == 2 then seen.buttons = M.find(" 20 M ", 4) and M.find(" 24 H ", 4); return R.tap(" 24 H ", "Aaron", 4) end
  if step == 3 then
    seen.long = M.find("LAST 30 MINUTES", 4) and M.find("one value every 10 minutes", 4) and not M.find("No samples", 4)
    H.screen("panel-24h")
    return R.tap(" 20 M ", "Aaron", 4)
  end
  seen.short = M.find("one sample every 30 s", 4) ~= nil
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.buttons and seen.long, "the panel page's 24 H: one value every 10 minutes")
check(seen.short, "20 M: the samples, as before")
local saved = files.loadTable(dir .. "/lens-history.cfg")
check(saved and saved.panels and saved.panels.Power and #saved.panels.Power.values >= 3, "lens-history.cfg keeps them")

local start = M.time
seen = {}
step = 0
ok = R.run{ cfg = CFG, dir = "hist", keep = true, agents = { power }, script = function(t)
  if t < start + 5 then return nil end
  step = step + 1
  if step == 1 then return R.tap("Power", "Aaron", 3) end
  if step == 2 then return R.tap(" 24 H ", "Aaron", 4) end
  seen.kept = M.find("one value every 10 minutes", 4) and not M.find("No samples", 4)
  return "stop"
end }
check(ok and seen.kept, "after a restart the 24 hours are still there")

seen = {}
ok = R.run{ cfg = "return { panels = { { label = \"Power\", value = \"lumen_fill_ratio\" } } }", dir = "nohist",
  agents = { power }, script = function(t)
  if t < 20 then return nil end
  if not seen.tapped then seen.tapped = true; return R.tap("Power", "Aaron", 3) end
  seen.none = not M.find(" 24 H ", 4)
  return "stop"
end }
check(ok and seen.none, "without history = true: no 24 H")

H.done()
