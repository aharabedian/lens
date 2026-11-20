-- test_flash.lua: a new BAD alert flashes in the HUD: through lens-hub with a Glasses Terminal, the block that lists it
-- blinks (its backdrop at 0.9, then at its own alpha, each tick) for 10 seconds, then stays as before; a new WARN, and
-- a new BAD on a muted node, don't flash; what it costs in calls.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local glassesMock = require("glasses")

local ore = R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
  m:beginCycle()
  if now >= 20 then m:alert("power:mac2", "bad", "Macerator 2: no power") end
  if now >= 50 then m:alert("idle:wash1", "warn", "Washer 1 idle") end
end }
local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m, now)
  m:beginCycle()
  if now >= 80 then m:alert("reactor:N-3", "bad", "Reactor N-3: fault signal") end
end }

local G = glassesMock.new()
-- The block's backdrop: the widest rect.
local function backdrop()
  local best
  for _, s in ipairs(G.live()) do
    if s.kind == "rect" and s.visible ~= false and (not best or (s.w or 0) > (best.w or 0)) then best = s end
  end
  return best
end

M.setTime(0)
local alphas, after, warnAlphas, mutedAlphas = {}, {}, {}, {}
local callsAt20, callsAt31
local step = 0
local ok, err = R.run{ cfg = "return {}", agents = { ore, power }, keyboard = true, terminals = { gl000000 = G },
  script = function(t)
  local b = backdrop()
  local a = b and b.alpha
  if t >= 18 and t < 19 and not callsAt20 then callsAt20 = G.calls end
  if t >= 21 and t < 31 then alphas[#alphas + 1] = a end
  if t >= 31 and not callsAt31 then callsAt31 = G.calls end
  if t >= 33 and t < 40 then after[#after + 1] = a end
  if t >= 52 and t < 60 then warnAlphas[#warnAlphas + 1] = a end
  if t >= 60 and step == 0 then
    step = 1
    local _, y = M.find("NODES", 2)
    return R.tap("power-room", "Aaron", y)
  end
  if step == 1 then step = 2; return R.tap(" 1 H ", "Aaron", 3) end
  if step == 2 then step = 3; return R.tap("DONE", "Aaron", 1) end
  if t >= 82 and t < 90 then mutedAlphas[#mutedAlphas + 1] = a end
  if t >= 92 then return "stop" end
  return nil
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
local function has(list, v) for _, x in ipairs(list) do if math.abs((x or -1) - v) < 0.001 then return true end end end
local function only(list, v) for _, x in ipairs(list) do if math.abs((x or -1) - v) > 0.001 then return false end end return #list > 0 end
check(has(alphas, 0.9) and has(alphas, 0.35), "a new BAD alert: the block blinks between 0.9 and its own alpha")
check(only(after, 0.35), "after 10 seconds it stays at its own alpha")
check(only(warnAlphas, 0.35), "a new WARN doesn't flash")
check(only(mutedAlphas, 0.35), "a new BAD on a muted node doesn't flash")
local cost = callsAt31 - callsAt20
check(cost <= 60, ("10 seconds of flashing and the alert itself cost %d calls"):format(cost))

H.done()
