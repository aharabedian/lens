-- test_group.lua: grouped alerts through lens-hub: a node with 3 or more alerts is one row on the dashboard (its count,
-- how many are bad, the worst level's tag), one with fewer is listed as before; tapping the group opens the node page
-- with each alert, where tapping one acknowledges it. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local C = require("lens.gui").C

local ore = R.agent{ node = "prism-ore", role = "prism", cycle = function(m)
  m:beginCycle()
  m:alert("power:mac2", "bad", "Macerator 2: no power")
  m:alert("power:mac3", "bad", "Macerator 3: no power")
  m:alert("idle:wash1", "warn", "Washer 1 idle")
  m:alert("idle:cent1", "warn", "Centrifuge 1 idle")
end }
local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m)
  m:beginCycle()
  m:alert("heat:N-2", "warn", "N-2 heat 86%")
end }

M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
local seen = {}
local ok, err = R.run{ cfg = "return {}", agents = { ore, power }, script = function(t)
  if t < 15 then return nil end
  if not seen.dash then
    seen.dash = true
    local x, y = M.find("prism-ore: 4 alerts (2 bad) ▶", 3)
    seen.group = x and M.bgAt(2, y) == C.bad and M.find("ALERTS (5)", 3) and not M.find("Macerator 2", 3)
    seen.single = M.find("N-2 heat 86%", 3) ~= nil
    H.screen("group-portrait")
    return R.tap("prism-ore: 4 alerts", "Aaron", 3)
  end
  if not seen.page then
    seen.page = true
    seen.each = M.find("Node: prism-ore", 1) and M.find("ALERTS (4)", 3) and M.find("Macerator 2: no power", 3)
      and M.find("Centrifuge 1 idle", 3)
    return R.tap("Washer 1 idle", "Aaron", 3)
  end
  seen.acked = M.find("✓ Aaron  Washer 1 idle", 3) ~= nil
  return "stop"
end }
M.aspect = nil
M.resize(160, 50)
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.group, "4 alerts from one node: one row, how many are bad, the worst level's tag")
check(seen.single, "a node with one alert: listed as before")
check(seen.each, "tapping the group opens the node page with each alert")
check(seen.acked, "tapping an alert there acknowledges it")

H.done()
