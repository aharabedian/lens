-- test_welcome.lua: Welcome back through lens-hub with a Glasses Terminal: glasses off for a while, then on again,
-- shows a block at the top of that player's HUD for 20 seconds with how long they were away, the alerts that started
-- meanwhile (how many still on, the longest) and the nodes that restarted; a short break shows nothing. Whether logging
-- out sends glasses_off is a probe (lens-discover --events); the mock sends it.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local glassesMock = require("glasses")

local ore = R.agent{ node = "prism-ore", role = "prism", restartAt = { 120 }, cycle = function(m, now)
  m:beginCycle()
  if now >= 60 and now < 100 then m:alert("idle:wash1", "warn", "Washer 1 idle") end
  if now >= 150 then m:alert("power:mac2", "bad", "Macerator 2: no power") end
end }

local G = glassesMock.new()
local function hudSays(text)
  for _, s in ipairs(G.live()) do if s.visible ~= false and (s.text or ""):find(text, 1, true) then return true end end
  return false
end

M.setTime(0)
local seen = {}
local step = 0
local ok, err = R.run{ cfg = "return {}", agents = { ore }, terminals = { gl000000 = G }, script = function(t)
  if t < 5 then return nil end
  step = step + 1
  if step == 1 then return { "glasses_on", "gl000000", "Aaron", 854, 480 } end
  if step == 2 then return { "glasses_off", "gl000000", "Aaron" } end
  if t < 20 then step = step - 1; return nil end
  if step == 3 then return { "glasses_on", "gl000000", "Aaron", 854, 480 } end   -- after 15 s: too short
  if step == 4 then seen.short = not hudSays("Welcome back"); return { "glasses_off", "gl000000", "Aaron" } end
  if t < 200 then step = step - 1; return nil end
  if step == 5 then seen.onAt = t; return { "glasses_on", "gl000000", "Aaron", 854, 480 } end
  if t < seen.onAt + 2 then step = step - 1; return nil end
  if step == 6 then
    seen.welcome = hudSays("Welcome back") and hudSays("away 3m") and hudSays("2 alerts meanwhile")
      and hudSays("1 still on") and hudSays("Longest: Macerator 2: no power") and hudSays("Restarted: prism-ore")
    H.glasses("welcome", G)
    return nil
  end
  if t < seen.onAt + 25 then step = step - 1; return nil end
  seen.gone = not hudSays("Welcome back")
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.short, "glasses off for 15 seconds: nothing")
check(seen.welcome, "off for minutes: how long, the alerts meanwhile, how many still on, the longest, restarts")
check(seen.gone, "the block goes after 20 seconds")

H.done()
