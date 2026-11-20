-- test_log.lua: the alert log kept across restarts: the real-time clock (a file's modification time), the log
-- file (lens.hub.logbook), times as text (frame.when, with and without a time zone), and through lens-hub: an alert
-- that ended is still on LOG after a restart, with when lens-hub started and stopped. The timeline (bands per node,
-- hour labels, 12 H / 24 H), on a 3 x 4 screen with a night's log. Previews: make screens.
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
local timeline = require("lens.hub.timeline")

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

---------------------------------------------------------------- the timeline's bands
do
  local now = 1795154400 + 12 * 3600            -- 18:00 UTC; 12 hours in 12 columns: an hour each
  local entries = {
    { kind = "alert", node = "prism-ore", level = "warn", since = now - 11.5 * 3600, at = now - 9.5 * 3600 },
    { kind = "alert", node = "prism-ore", level = "bad", since = now - 10.2 * 3600, at = now - 10.1 * 3600 },
    { kind = "alert", node = "power-room", level = "bad", since = now - 20 * 3600, at = now - 19 * 3600 },   -- before
    { kind = "restart", node = "power-room", at = now - 2.5 * 3600 },
    { kind = "start", at = now - 5 * 3600 },
    { node = "hub", level = "warn", since = now - 0.5 * 3600 },                       -- happening now
  }
  local b = timeline.bands(entries, now, 12 * 3600, 12)
  local ore = b.rows[3]
  check(#b.rows == 3 and b.rows[1].node == "hub" and b.rows[2].node == "power-room" and ore.node == "prism-ore",
    "a row per node with something in the span, by name")
  check(ore.cells[1] == "warn" and ore.cells[2] == "bad" and ore.cells[3] == "warn" and ore.cells[4] == nil,
    "each column: the worst alert in it")
  check(next(b.rows[2].cells) == nil and b.rows[2].marks[10], "a restart is a mark; alerts before the span aren't shown")
  check(b.rows[1].cells[12] == "warn" and b.step == 3600, "an alert happening now reaches the last column")
  check(#timeline.bands(entries, now, 12 * 3600, 12, 2).rows == 2 and timeline.bands(entries, now, 12 * 3600, 12, 2).more == 1,
    "at most max rows; more says how many weren't shown")
  local ticks = timeline.ticks(now, 12 * 3600, 60, 0)
  check(ticks[1][2] == "08:00" and ticks[#ticks][2] == "now" and ticks[#ticks][1] == 58, "with a time zone: clock hours, then now")
  local back = timeline.ticks(now, 12 * 3600, 60)
  check(back[1][2] == "-10h" and back[2][2] == "-8h", "without: hours ago")
  check(timeline.ticks(now, 24 * 3600, 60, 0)[1][2] == "20:00", "24 hours: every 4")
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

-- A night's log on a 3 x 4 screen: the timeline over the last 12 hours, then 24.
do
  local d = H.TMP .. "/night"
  os.execute('rm -rf "' .. d .. '" && mkdir -p "' .. d .. '"')
  start = M.time
  local now = M.epoch + start
  local L = logbook.new(d .. "/lens-log.cfg")
  local function logAlert(node, level, text, ago, lasted)
    L:add{ kind = "alert", node = node, id = text, level = level, text = text, since = now - ago, at = now - ago + lasted }
  end
  logAlert("power-room", "bad", "Reactor N-1: fault signal", 20 * 3600, 900)
  logAlert("power-room", "warn", "N-2 heat 86%", 4.5 * 3600, 720)
  logAlert("prism-ore", "warn", "ore stalled 23m - 31k waiting", 3.4 * 3600, 1080)
  logAlert("hub", "warn", "Ore line busy on low power", 2.6 * 3600, 2580)
  logAlert("prism-ore", "bad", "Macerator 2: no power", 2.4 * 3600, 840)
  logAlert("power-room", "warn", "Main low: 24.6%", 2.6 * 3600, 2820)
  assert(L:save())
  M.resize(73, 50)
  M.aspect = { 3, 4 }
  seen = {}
  ok, err = R.run{ cfg = "return { timezone = 0 }", dir = "night", keep = true, agents = { ore(start - 15) },
    keyboard = true, script = function(t)
    if t < start + 3 then return nil end
    if not seen.opened then seen.opened = true; return R.tap(" LOG ", "Aaron", 1) end
    if not seen.at12 then
      seen.at12 = true
      local _, y = M.find("power-room", 4)
      seen.twelve = M.find("TIMELINE", 3) and M.find("last 12 hours, a column is 12 minutes", 3) and M.find("now", 4)
        and y and M.find("prism-ore", y) and M.find("hub", y) and M.bgAt(72, y) == 0x1a2129
        and M.find("NOW (1)", 8) and M.find("EARLIER (", 8)
      H.screen("log-timeline-portrait")
      return R.tap(" 24 H ", "Aaron", 1)
    end
    if not seen.at24 then
      seen.at24 = true
      seen.day = M.find("last 24 hours, a column is 25 minutes", 3) ~= nil
      return R.tap("DONE", "Aaron", 1)
    end
    return "stop"
  end }
  M.aspect = nil
  M.resize(160, 50)
  check(ok, "lens-hub runs on a 3 x 4 screen" .. (ok and "" or (": " .. tostring(err))))
  check(seen.twelve, "LOG: a timeline of the last 12 hours, a band per node, above now and earlier")
  check(seen.day, "24 H: the last 24 hours")
end

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
