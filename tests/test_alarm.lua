-- test_alarm.lua: the alarm output: settings checked; through lens-hub with a redstone card: 15 on its side while a
-- BAD alert is neither acknowledged nor muted, 0 once it's acknowledged (straight away), set only on change, 0 on
-- exit; level = "warn" counts warns; no card: the footer says so. (The probe, lens-discover --redstone: test_discover.)
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local config = require("lens.hub.config")

check(config.check({ alarm = { side = "north" } }).alarm.level == "bad", "alarm: level defaults to bad")
check(select(2, config.check({ alarm = { side = "sideways" } })):find("a side", 1, true), "an unknown side is refused")
check(select(2, config.check({ alarm = { side = "top", level = "loud" } })):find("alarm.level", 1, true), "level: bad or warn")

local function ore()
  return R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
    m:beginCycle()
    if now >= 20 and now < 60 then m:alert("power:mac2", "bad", "Macerator 2: no power") end
    if now >= 70 then m:alert("idle:wash1", "warn", "Washer 1 idle") end
  end }
end

M.setTime(0)
local rs = M.redstone()
local seen = {}
local ok, err = R.run{ cfg = 'return { alarm = { side = "north" } }', agents = { ore() },
  components = { rs000000 = { type = "redstone", proxy = rs.proxy } }, script = function(t)
  if t >= 120 then return "stop" end
  if t < 15 then seen.before = rs.outputs[2] or 0; return nil end
  if t < 25 then return nil end
  if seen.on == nil then seen.on, seen.calls = rs.outputs[2] or false, rs.calls; return nil end
  if not seen.acked then
    seen.acked = true
    seen.steady = rs.calls == seen.calls
    return R.tap("Macerator 2: no power", "Aaron", 3)
  end
  if seen.off == nil then seen.off = rs.outputs[2] or false; return nil end
  if t < 80 then return nil end
  seen.warnOnly = rs.outputs[2]
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.before == 0 and seen.on == 15, "a BAD alert: 15 on the alarm's side")
check(seen.steady, "set only when it changes")
check(seen.off == 0, "acknowledging it turns the alarm off straight away")
check(seen.warnOnly == 0, "a WARN doesn't, with level = bad")

M.setTime(0)
rs = M.redstone()
seen = {}
ok = R.run{ cfg = 'return { alarm = { side = "top", level = "warn" } }', dir = "warn", agents = { ore() },
  components = { rs000000 = { type = "redstone", proxy = rs.proxy } }, script = function(t)
  if t < 80 then return nil end
  seen.warn = rs.outputs[1]
  return "stop"
end }
check(ok and seen.warn == 15 and rs.outputs[1] == 0, "level = warn: a WARN turns it on (top); 0 on exit")

seen = {}
ok = R.run{ cfg = 'return { alarm = { side = "north" } }', dir = "nocard", agents = { ore() }, script = function(t)
  if t < 30 then return nil end
  seen.footer = M.find("alarm: no redstone card in the hub computer", 50) ~= nil
  return "stop"
end }
check(ok and seen.footer, "no card: the footer says so")

H.done()
