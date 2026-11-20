-- test_node.lua: the node page. The hub's count of snapshots whole and cut short (core:traffic) from parts on their
-- own; through lens-hub on a 3 x 4 screen: tapping a node shows its health, role, version, how often it reports, its
-- distance, snapshots, alerts, its last 24 hours, its metrics and the views that read them; a node that went silent
-- has FORGET, which drops it from the dashboard. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local codec = require("lens.codec")
local metrics = require("lens.metrics")
local core = require("lens.hub.core")

---------------------------------------------------------------- snapshots whole and cut short
do
  local m = metrics.new{ role = "prism", clock = function() return 0 end }
  local g = m:gauge("prism_machine_state", "state")
  for i = 1, 300 do g:set(1, { machine = ("machine-with-a-long-name-%03d"):format(i), state = "running" }) end
  local enc = codec.encoder{ node = "prism-ore", role = "prism", boot = 3, interval = 5 }
  local hub = core.new{ node = "hub" }
  for _, p in ipairs(enc:describe(m:describe())) do hub:receive(p, "a", 0, 7) end
  local first = enc:snapshot(m:snapshot())
  check(#first > 1, "a big snapshot comes in parts")
  for _, p in ipairs(first) do hub:receive(p, "a", 1, 7) end
  local t = hub:traffic("prism-ore")
  check(t.whole == 1 and t.cut == 0 and t.distance == 7, "all its parts: one whole, and the distance")
  local second = enc:snapshot(m:snapshot())
  hub:receive(second[1], "a", 6)                      -- the rest are lost
  for _, p in ipairs(enc:snapshot(m:snapshot())) do hub:receive(p, "a", 11) end
  t = hub:traffic("prism-ore")
  check(t.whole == 2 and t.cut == 1, "a part lost: that one is cut short when the next begins")
  hub:forget("prism-ore")
  check(hub:traffic("prism-ore") == nil and #hub:nodes(12) == 0, "forget drops the node")
end

---------------------------------------------------------------- through lens-hub
local power = R.agent{ node = "power-room", role = "lumen", distance = 12, cycle = function(m, now)
  m:beginCycle()
  m:gauge("lumen_stored_eu", "stored", "EU"):set(7.9e9)
  m:gauge("lumen_capacity_eu", "capacity", "EU"):set(19.3e9)
  m:gauge("lumen_reactor_on", "on"):set(1, { reactor = "N-1" })
  m:gauge("lumen_reactor_on", "on"):set(0, { reactor = "N-3" })
  if now >= 10 then m:alert("reactor:N-3", "bad", "Reactor N-3: fault signal") end
end }
local ore = R.agent{ node = "prism-ore", role = "prism", stopAt = 20, cycle = function(m)
  m:beginCycle()
  m:gauge("prism_backlog_items", "b", "items"):set(15100, { process = "ore" })
end }

local CFG = [[return { panels = {
  { label = "Power", value = "sum(lumen_stored_eu) / sum(lumen_capacity_eu)", format = "percent" },
  { label = "Ore", value = "sum(prism_backlog_items)", unit = "items" },
} }]]

M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
local seen = {}
local ok, err = R.run{ cfg = CFG, agents = { power, ore }, script = function(t)
  if t < 45 then return nil end
  if not seen.opened then
    seen.opened = true
    local _, y = M.find("NODES", 2)
    return R.tap("power-room", "Aaron", y)
  end
  if not seen.page then
    seen.page = true
    seen.header = M.find("Node: power-room", 1) and M.find("BAD", 3) and M.find("lumen · boot 3", 3)
      and M.find("reports every 5s, last", 3) and M.find("12 m away", 3) and M.find("whole, 0 cut short", 3)
      and not M.find("FORGET", 1)
    seen.alerts = M.find("ALERTS (1)", 3) and M.find("Reactor N-3: fault signal", 3)
    seen.band = M.find("LAST 24 HOURS", 3) and M.find("a column is 25 minutes", 3)
    seen.metrics = M.find("METRICS (3)", 3) and M.find("lumen_capacity_eu  EU", 3) and M.find("gauge · 2 series", 3)
    seen.readBy = M.find("READ BY", 3) and M.find("Power", 3) and not M.find("Ore", 20)
    H.screen("node-portrait")
    return R.tap("DONE", "Aaron", 1)
  end
  if not seen.stale then
    seen.stale = true
    local _, y = M.find("NODES", 2)
    return R.tap("prism-ore", "Aaron", y)
  end
  if not seen.forget then
    seen.forget = true
    seen.forgetButton = M.find("Node: prism-ore", 1) and M.find("STALE", 3) and M.find(" FORGET ", 1)
    seen.forgotAt = t
    return R.tap(" FORGET ", "Aaron", 1)
  end
  if t < seen.forgotAt + 2 then return nil end                -- the next tick clears its stale alert
  local _, y = M.find("NODES", 2)
  seen.gone = M.find("1 node ", 1) and not M.find("prism-ore", y)
  return "stop"
end }
M.aspect = nil
M.resize(160, 50)
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.header, "tapping a node: health, role and version, how often it reports, distance, snapshots")
check(seen.alerts, "its alerts")
check(seen.band, "its last 24 hours")
check(seen.metrics, "its metrics, with type, unit and series")
check(seen.readBy, "the views that read them")
check(seen.forgetButton, "a node that stopped reporting has FORGET")
check(seen.gone, "FORGET drops it from the dashboard")

H.done()
