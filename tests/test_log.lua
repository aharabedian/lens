-- test_log.lua: the alert log kept across restarts: the real-time clock (a file's modification time), the log
-- file (lens.hub.logbook), times as text (frame.when, with and without a time zone), and through lens-hub: an alert
-- that ended is still on LOG after a restart, with when lens-hub started and stopped. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local clock = require("lens.hub.clock")
local logbook = require("lens.hub.logbook")
local alerts = require("lens.hub.alerts")
local config = require("lens.hub.config")
local frame = require("lens.hub.frame")
local files = require("lens.files")

---------------------------------------------------------------- the clock
do
  local ms, writes = 1795154400000, 0
  local fs = { lastModified = function() writes = writes + 1; return ms end }
  local c = clock.new(fs, H.TMP .. "/clock")
  check(c:at(100) == 1795154400 and c.real, "the clock reads real time from the file it writes")
  ms = ms + 5000                               -- the file's time isn't read again for an hour
  check(c:at(130) == 1795154430 and writes == 1, "then carries on with uptime")
  ms = 1795154400000 + 3700 * 1000
  check(c:at(3800) == 1795158100 and writes == 2, "and reads the file again after an hour")
  local none = clock.new({ lastModified = function() return 0 end }, H.TMP .. "/clock2")
  check(none:at(42) == 42 and not none.real, "lastModified 0: uptime, and real is false")
  local broken = clock.new({ lastModified = function() error("no") end }, H.TMP .. "/clock3")
  check(broken:at(7) == 7 and not broken.real, "lastModified failing: uptime")
  check(clock.new(fs, H.TMP .. "/no/such/dir/clock"):at(9) == 9, "a file it can't write: uptime")
end

---------------------------------------------------------------- times as text
do
  local now = 1795154400 + 40 * 60              -- Friday 20 November 2026, 06:40 UTC
  check(frame.when(now - 3 * 3600 - 12 * 60, now) == "3h12m ago", "no time zone: how long ago")
  check(frame.when(now - 60 * 60, now, 0) == "05:40", "with a time zone: the clock time that day")
  check(frame.when(now - 13 * 3600, now, 0) == "Thu 17:40", "the day before: weekday and time")
  check(frame.when(now - 6 * 86400, now, 0) == "Sat 06:40", "within the week")
  check(frame.when(now - 8 * 86400, now, 0) == "12 Nov", "earlier: the date")
  check(frame.when(now - 2 * 3600, now, -5) == "Thu 23:40" and frame.when(now, now, -5) == "01:40",
    "the time zone moves times and days")
  check(frame.when(now, now, 5.5) == "12:10", "half hours too")
  check(config.check({ timezone = -5 }) and config.check({ timezone = 5.5 }), "timezone: hours from UTC")
  check(select(2, config.check({ timezone = 20 })):find("timezone", 1, true)
    and select(2, config.check({ timezone = "CET" })):find("timezone", 1, true), "a timezone out of range is refused")
end

---------------------------------------------------------------- alerts that end
do
  local a = alerts.new()
  a:update(10, { { node = "n", id = "x", level = "warn", text = "low" } })
  a:update(20, { { node = "n", id = "x", level = "bad", text = "very low" } })
  local r = a:update(30, {})
  local e = r.ended[1]
  check(#r.ended == 1 and e.key == "n/x" and e.level == "bad" and e.since == 10 and e.ended == 30,
    "update says which alerts ended: their worst level, start and end")
end

---------------------------------------------------------------- the log file
do
  local path = H.TMP .. "/lens-log.cfg"
  local L = logbook.new(path, 3)
  check(L.count == 0 and L:save(), "no file: an empty log")
  L:add{ kind = "start", at = 100 }
  L:add{ kind = "alert", node = "prism-ore", id = "m", level = "bad", text = 'mac2 "no power"\nagain', since = 110,
    at = 140 }
  check(L.dirty and L:list()[1].kind == "alert" and L:list()[2].kind == "start", "newest first")
  check(L:save() and not L.dirty and files.exists(path), "saved")
  local again = logbook.new(path, 3)
  local first = again:list()[1]
  check(again.count == 2 and first.text == 'mac2 "no power"\nagain' and first.since == 110 and first.at == 140
    and again:list()[2].kind == "start", "read back as it was written")
  for i = 1, 3 do again:add{ kind = "stop", at = 200 + i } end
  check(again.count == 3 and again:list()[1].at == 203 and again:list()[3].at == 201, "keeps the newest `keep`")
  local f = io.open(path, "w"); f:write("return { entries = { 1, { kind = 'x' }, { kind = 'start', at = 5 } } }"); f:close()
  check(logbook.new(path).count == 1, "entries without a kind and time are skipped")
  f = io.open(path, "w"); f:write("garbage {"); f:close()
  check(logbook.new(path).count == 0, "a broken file: an empty log (the next save replaces it)")
end

---------------------------------------------------------------- through lens-hub, across a restart
local function ore(from)
  from = from or 0
  return R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
    m:beginCycle()
    m:gauge("prism_backlog_items", "b", "items"):set(4200, { process = "ore" })
    if now >= from + 10 and now < from + 40 then m:alert("machine:mac2", "bad", "mac2: no power") end
  end }
end

M.setTime(0)
M.resize(160, 50)
local seen = {}
local ok, err, dir = R.run{ cfg = "return {}", dir = "restart", agents = { ore() }, keyboard = true, script = function(t)
  if t < 50 then return nil end
  if not seen.opened then seen.opened = true; return R.tap(" LOG ", "Aaron", 1) end
  if not seen.first then
    seen.first = M.find("EARLIER (2)", 1) and M.find("kept in lens-log.cfg", 1) and M.find("mac2: no power", 3)
      and M.find(" ago, lasted ", 3) and M.find("lens-hub started", 3)
    return R.tap("DONE", "Aaron", 1)
  end
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.first, "LOG: the alert that ended and when lens-hub started, with how long ago")
local saved = files.loadTable(dir .. "/lens-log.cfg")
local kinds = {}
for _, e in ipairs(saved and saved.entries or {}) do kinds[#kinds + 1] = e.kind end
check(table.concat(kinds, " ") == "stop alert start", "lens-log.cfg has them, and lens-hub stopping")
local alert = saved.entries[2]
check(alert.node == "prism-ore" and alert.level == "bad" and alert.at - alert.since >= 25 and alert.at - alert.since <= 35
  and math.abs(alert.since - (M.epoch + 10)) <= 5, "in real time: when it started and ended")

-- Restarted, with a time zone: the log is still there, with clock times.
local start = M.time
seen = {}
ok, err = R.run{ cfg = "return { timezone = 0 }", dir = "restart", keep = true, agents = {}, keyboard = true,
  script = function(t)
  if t < start + 3 then return nil end
  if not seen.opened then seen.opened = true; return R.tap(" LOG ", "Aaron", 1) end
  if not seen.after then
    seen.after = M.find("NOW (0)", 1) and M.find("EARLIER (4)", 1) and M.find("mac2: no power", 3)
      and M.find("06:00, lasted ", 3) and M.find("lens-hub stopped", 3) and M.find("lens-hub started", 3)
    H.screen("log-kept")
    return R.tap("DONE", "Aaron", 1)
  end
  return "stop"
end }
check(ok, "lens-hub restarts" .. (ok and "" or (": " .. tostring(err))))
check(seen.after, "after a restart LOG still has the alert, with its clock time, and the restart")

-- No usable clock: the log still works, in uptime.
M.noClock = true
seen = {}
start = M.time
ok = R.run{ cfg = "return {}", dir = "noclock", agents = { ore(start) }, script = function(t)
  if t < start + 50 then return nil end
  if not seen.opened then seen.opened = true; return R.tap(" LOG ", "Aaron", 1) end
  seen.noClock = M.find("lasted", 3) ~= nil
  return "stop"
end }
M.noClock = nil
check(ok and seen.noClock, "without a real clock the log still lists alerts")

H.done()
