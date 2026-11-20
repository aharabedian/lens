-- test_mute.lua: muting. lens.hub.mutes on its own (a node or an alert, for a time or until it clears); through
-- lens-hub: MUTE 1 H on a node page, then the dashboard (MUTED, the time left, counts, health), no beep and nothing in
-- the HUD for its alerts, LOG saying who muted what, lens-board.cfg keeping it, UNMUTE; one alert muted until it
-- clears; `editors`. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local mutes = require("lens.hub.mutes")
local files = require("lens.files")
local glassesMock = require("glasses")

---------------------------------------------------------------- on its own
do
  local mu = mutes.new()
  mu:add{ node = "prism-ore", ends = 1000, by = "Aaron", at = 0 }
  mu:add{ node = "power-room", key = "power-room/heat", by = "Bob", at = 0 }
  check(mu:of({ key = "prism-ore/x", node = "prism-ore" }).by == "Aaron", "a node's mute covers each of its alerts")
  check(mu:of({ key = "power-room/heat", node = "power-room" }).by == "Bob"
    and mu:of({ key = "power-room/other", node = "power-room" }) == nil, "an alert's mute covers only that alert")
  check(mu:node("prism-ore") and not mu:node("power-room"), "node(): a node's own mute only")
  local alerts = { { key = "power-room/heat", node = "power-room" } }
  check(#mu:expire(999, alerts) == 0, "nothing ends early")
  local ended = mu:expire(1000, alerts)
  check(#ended == 1 and ended[1].node == "prism-ore", "a timed mute ends at its time")
  check(#mu:expire(1001, {}) == 1 and #mu:list() == 0, "an alert's mute ends when the alert clears")
  mu:add{ node = "prism-ore", by = "Aaron", at = 0 }
  check(#mu:expire(5, { { key = "prism-ore/a", node = "prism-ore" } }) == 0 and #mu:expire(6, {}) == 1,
    "a node muted until it clears: until it has no alerts")
  mu:add{ node = "a", ends = 9 }
  mu:add{ node = "a", ends = 20 }
  local again = mutes.new(mu:list())
  check(#again:list() == 1 and again:list()[1].ends == 20 and again:remove("a") and #again:list() == 0,
    "one mute per node or alert; saved and read back; removed")
  check(#mutes.new({ { node = 3 }, "x", { node = "ok" } }):list() == 1, "bad saved entries are skipped")
end

---------------------------------------------------------------- through lens-hub
local function agents()
  return {
    R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
      m:beginCycle()
      m:gauge("prism_backlog_items", "b", "items"):set(15100, { process = "ore" })
      if now >= 10 then m:alert("power:mac2", "bad", "Macerator 2: no power") end
      if now >= 90 then m:alert("power:mac3", "bad", "Macerator 3: no power") end
      if now >= 10 and now < 150 then m:alert("idle:wash1", "warn", "Washer 1 idle") end
    end },
    R.agent{ node = "power-room", role = "lumen", cycle = function(m)
      m:beginCycle()
      m:gauge("lumen_fill_ratio", "f"):set(0.9)
    end },
  }
end

local G = glassesMock.new()
local function hudSays(text)
  for _, s in ipairs(G.live()) do if s.visible ~= false and (s.text or ""):find(text, 1, true) then return true end end
  return false
end

M.setTime(0)
local seen = {}
local beeps
local ok, err, dir = R.run{ cfg = 'return { editors = { "Aaron" } }', agents = agents(), keyboard = true,
  terminals = { gl000000 = G }, script = function(t)
  if t < 30 then return nil end
  if not seen.opened then
    seen.opened = true
    seen.before = M.find(" BAD ", 1) and hudSays("Macerator 2")
    local _, y = M.find("NODES", 2)
    return R.tap("prism-ore", "Aaron", y)
  end
  if not seen.offered then
    seen.offered = true
    seen.choices = M.find("MUTE", 3) and M.find(" 1 H ", 3) and M.find(" 4 H ", 3) and M.find(" UNTIL IT CLEARS ", 3)
    return R.tap(" 1 H ", "Aaron", 3)
  end
  if not seen.mutedPage then
    seen.mutedPage = true
    seen.page = M.find("MUTED by Aaron, 1h00m left", 3) and M.find(" UNMUTE ", 3)
    H.screen("mute-node")
    return R.tap("DONE", "Aaron", 1)
  end
  if not seen.dash then
    seen.dash = true
    beeps = M.beeps
    seen.dashboard = M.find(" OK ", 1) and M.find("0 bad, 0 warn, 2 muted", 1) and M.find("MUTED", 3)
      and (M.find("muted 59m", 3) or M.find("muted 1h00m", 3))
    H.screen("mute-dashboard")
    return nil
  end
  if t < 100 then return nil end
  if not seen.later then
    seen.later = true
    seen.noBeep = M.beeps == beeps and M.find("prism-ore: 3 alerts (2 bad) ▶", 3) and M.find("3 muted", 1)
    seen.noHud = not hudSays("Macerator")
    return R.tap(" LOG ", "Aaron", 1)
  end
  if not seen.log then
    seen.log = true
    seen.logged = M.find("Aaron muted prism-ore for 1h00m", 3) ~= nil
    return R.tap("DONE", "Aaron", 1)
  end
  if not seen.bob then
    seen.bob = true
    local _, y = M.find("NODES", 2)
    return R.tap("prism-ore", "Bob", y)
  end
  if not seen.bobPage then
    seen.bobPage = true
    seen.bobNoMute = M.find("MUTED by Aaron", 3) and not M.find("UNMUTE", 3)
    return R.tap("DONE", "Bob", 1)
  end
  if not seen.unmuting then
    seen.unmuting = true
    local _, y = M.find("NODES", 2)
    return R.tap("prism-ore", "Aaron", y)
  end
  if not seen.unmuted then
    seen.unmuted = true
    return R.tap(" UNMUTE ", "Aaron", 3)
  end
  if not seen.alertMute then
    seen.alertMute = true
    seen.offeredAgain = M.find(" 1 H ", 3) ~= nil
    local _, y = M.find("Washer 1 idle", 3)
    return R.tap(" MUTE ", "Aaron", y)
  end
  if not seen.alertMuted then
    seen.alertMuted = true
    local _, y = M.find("Washer 1 idle", 3)
    seen.oneAlert = y and M.row(y):find("muted · for", 1, true) and M.row(y):find("UNMUTE", 1, true)
    return R.tap("DONE", "Aaron", 1)
  end
  if t < 160 then return nil end
  seen.cleared = M.find("2 bad, 0 warn", 1) and not M.find("muted", 1)
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.before, "before: a bad alert, in the HUD too")
check(seen.choices, "the node page offers MUTE 1 H, 4 H and UNTIL IT CLEARS")
check(seen.page, "muted: by whom and how long is left, and UNMUTE")
check(seen.dashboard, "the dashboard: health leaves it out, its alerts count as muted, MUTED, the time left")
check(seen.noBeep, "a new bad alert on a muted node doesn't beep")
check(seen.noHud, "and muted alerts aren't in the HUD")
check(seen.logged, "LOG says who muted what, for how long")
check(seen.bobNoMute, "someone not in editors sees the mute but can't change it")
check(seen.offeredAgain, "UNMUTE ends it")
check(seen.oneAlert, "one alert muted until it clears")
check(seen.cleared, "the mute ends when that alert clears")
local saved = files.loadTable(dir .. "/lens-board.cfg")
check(saved and type(saved.mutes) == "table" and #saved.mutes == 0, "lens-board.cfg keeps the mutes (none left now)")

H.done()
