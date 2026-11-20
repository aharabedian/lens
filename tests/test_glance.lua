-- test_glance.lua: glance mode through lens-hub on a 3 x 4 screen: after glance.after minutes without a tap the hub
-- draws at a third of its resolution (24 x 16) with the views picked for it and the two worst alerts; a tap goes back
-- to the full dashboard without pressing what's under it; no glance while an editor is open, none by default, and the
-- first page's panels when no views are picked; settings checked. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local config = require("lens.hub.config")

check(config.check({}).glance == false, "glance is off by default")
local c = config.check({ glance = { views = { "Power" } } })
check(c.glance.after == 5 and c.glance.views[1] == "Power", "glance: after defaults to 5 minutes")
check(config.check({ glance = true }).glance.after == 5, "glance = true: the defaults")
check(select(2, config.check({ glance = { after = 0 } })):find("glance.after", 1, true)
  and select(2, config.check({ glance = { views = { 3 } } })):find("glance.views", 1, true), "bad glance settings say what's wrong")

local function agents()
  return {
    R.agent{ node = "power-room", role = "lumen", cycle = function(m)
      m:beginCycle()
      m:gauge("lumen_fill_ratio", "f"):set(0.41)
      m:gauge("lumen_empty_seconds", "e", "s"):set(11520)
      m:alert("reactor:N-3", "bad", "Reactor N-3: fault signal")
    end },
    R.agent{ node = "prism-ore", role = "prism", cycle = function(m)
      m:beginCycle()
      m:gauge("prism_backlog_items", "b", "items"):set(15100, { process = "ore" })
      m:alert("idle:mac2", "warn", "Macerator 2 idle 4m with work waiting")
    end },
  }
end

local PANELS = [[panels = {
  { label = "Power", value = "lumen_fill_ratio", format = "percent" },
  { label = "Empty in", value = "min(lumen_empty_seconds)", format = "duration" },
  { label = "Ore", value = "sum(prism_backlog_items)", unit = "items" },
}]]

-- Text drawn inside the glance resolution (the mock keeps what was drawn outside it from before).
local function inGlance(text)
  local x, y = M.find(text)
  return x ~= nil and x <= 24 and y <= 16
end

M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
local seen = {}
local ok, err = R.run{ cfg = "return { glance = { after = 1, views = { \"Power\", \"Ore\" } }, " .. PANELS .. " }",
  agents = agents(), script = function(t)
  if t < 50 then return nil end
  if not seen.before then
    seen.before = true
    seen.full = M.resolution[1] == 73 and M.resolution[2] == 50
    return nil
  end
  if t < 65 then return nil end
  if not seen.glanced then
    seen.glanced = true
    seen.small = M.resolution[1] == 24 and M.resolution[2] == 16
    seen.content = inGlance("LENS") and inGlance("2 alerts") and inGlance("Power") and inGlance("41%")
      and inGlance("Ore") and inGlance("15.1k items") and not inGlance("Empty in")
      and inGlance("Reactor N-3") and inGlance("Macerator 2") and inGlance("Tap for the dashboard")
    H.screen("glance-portrait")
    return { "touch", "screen", 3, 3, 0, "Aaron" }           -- on the Power panel: wakes, doesn't open it
  end
  if not seen.woke then
    seen.woke = true
    seen.back = M.resolution[1] == 73 and M.find("NODES", 3) and not M.find("Panel: Power", 1)
    return R.tap(" LOG ", "Aaron", 1)
  end
  if t < 200 then return nil end                             -- LOG is open: no glance (it closes at about 125)
  seen.again = M.resolution[1] == 24
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.full, "the full resolution at first")
check(seen.small, "after a minute without a tap: a third of the resolution, 24 x 16")
check(seen.content, "health, the alert count, the views picked (not the others) and the two worst alerts")
check(seen.back, "a tap goes back to the dashboard without opening what was under it")
check(seen.again, "glance mode comes back once the editor has closed and a minute has passed")
check(M.resolution[1] == 73 and M.resolution[2] == 50, "on exit the screen gets its full resolution back")

-- Without views: the first page's first panels. Off by default.
seen = {}
ok = R.run{ cfg = "return { glance = { after = 1 }, " .. PANELS .. " }", dir = "default", agents = agents(),
  script = function(t)
  if t < 280 then return nil end
  seen.first = inGlance("Power") and inGlance("Empty in") and inGlance("Ore")
  return "stop"
end }
check(ok and seen.first, "no views picked: the first page's panels")
seen = {}
ok = R.run{ cfg = "return { " .. PANELS .. " }", dir = "off", agents = agents(), script = function(t)
  if t < 400 then return nil end
  seen.off = M.resolution[1] == 73
  return "stop"
end }
check(ok and seen.off, "without glance: never")
M.aspect = nil
M.resize(160, 50)

H.done()
