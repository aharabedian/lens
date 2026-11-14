-- test_units.lua: pure modules on their own: lens.metrics (the agent's registry) and lens.codec (envelope,
-- splitting into packets, decoding, reassembly).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local metrics = require("lens.metrics")
local codec = require("lens.codec")
local ser = M.serialization

local function raises(fn, pattern)
  local ok, err = pcall(fn)
  return not ok and (pattern == nil or tostring(err):find(pattern, 1, true) ~= nil)
end

local function clock() return M.time end

---------------------------------------------------------------- metrics: declaring
do
  local m = metrics.new{ role = "prism", clock = clock }
  check(raises(function() metrics.new{ role = "Prism" } end), "role must be lowercase a-z0-9_")
  check(raises(function() m:gauge("power_eu_stored", "x") end, "must start with prism_"), "names start with the role")
  check(raises(function() m:gauge("prism_Backlog", "x") end, "bad metric name"), "names are lowercase a-z0-9_")
  check(raises(function() m:counter("prism_items_routed", "x") end, "_total"), "counter names end in _total")

  local g = m:gauge("prism_backlog_items", "Items waiting", "items")
  check(m.dseq == 1, "declaring a metric moves dseq")
  check(m:gauge("prism_backlog_items", "Items waiting", "items") == g and m.dseq == 1,
    "declaring the same gauge again returns the same handle and leaves dseq alone")
  local c = m:counter("prism_items_routed_total", "Items moved", "items")
  check(raises(function() m:gauge("prism_items_routed_total", "x") end, "already a counter"), "a name keeps its type")
  check(raises(function() c:set(1) end, "use add") and raises(function() g:add(1) end, "use set"),
    "gauges set, counters add")
  check(raises(function() c:add(-1) end, "only go up"), "counters never go down")

  local d = m:describe()
  check(d.dseq == 2 and d.metrics.prism_backlog_items.type == "gauge" and d.metrics.prism_backlog_items.unit == "items"
    and d.metrics.prism_items_routed_total.type == "counter" and d.metrics.prism_items_routed_total.help == "Items moved",
    "describe lists every metric with type, help and unit")
end

---------------------------------------------------------------- metrics: labels and samples
do
  local m = metrics.new{ role = "prism", clock = clock }
  local g = m:gauge("prism_machine_state", "state")
  check(raises(function() g:set(1, { node = "x" }) end, "reserved"), "the node label is reserved for the hub")
  check(raises(function() g:set(1, { a = "1", b = "2", c = "3", d = "4", e = "5" }) end, "at most 4"),
    "at most 4 labels per series")
  check(raises(function() g:set(1, { Bad = "x" }) end, "bad label name"), "label names follow the metric name rules")
  check(raises(function() g:set(1, { a = {} }) end, "must be a string"), "label values are strings")

  g:set(1, { machine = "mac2", state = "down" })
  g:set(1, { state = "running", machine = "mac1" })
  g:set(0, { machine = "mac1", state = "idle" })
  g:set(7, { machine = 3, state = "running" })
  local b = m:gauge("prism_backlog_items", "backlog")
  b:set(4200)
  local s = m:snapshot().samples
  check(#s == 5 and s[1][1] == "prism_backlog_items" and s[1][2] == 4200 and s[1][3] == nil,
    "unlabelled series have no labels table; samples are sorted by name")
  check(s[2][3].machine == "3" and s[2][3].state == "running", "number label values become strings")
  check(s[3][3].machine == "mac1" and s[3][3].state == "idle" and s[4][3].state == "running" and s[5][3].machine == "mac2",
    "series of one metric are sorted by their labels")

  g:set(2, { machine = "mac1", state = "idle" })
  check(#m:snapshot().samples == 5, "setting a series again replaces its value")
  g:set(0 / 0, { machine = "mac1", state = "idle" })
  g:set(math.huge, { machine = "mac2", state = "down" })
  b:set(nil)
  check(#m:snapshot().samples == 2, "nil, NaN and infinity remove the series")
  g:remove({ machine = 3, state = "running" })
  check(#m:snapshot().samples == 1, "remove drops one series")
end

---------------------------------------------------------------- metrics: cycles, alerts, health
do
  M.setTime(100)
  local m = metrics.new{ role = "power", clock = clock }
  local g = m:gauge("power_eu_stored", "EU", "EU")
  local c = m:counter("power_eu_generated_total", "EU made", "EU")
  m:beginCycle()
  g:set(5)
  c:add(10, { gen = "t1" })
  check(m:snapshot().health == "ok" and #m:snapshot().alerts == 0, "no alerts: health ok")
  m:alert("lsc-low", "warn", "LSC below 25%")
  local snap = m:snapshot()
  check(snap.health == "warn" and snap.alerts[1].id == "lsc-low" and snap.alerts[1].age == 0,
    "health follows the worst alert; a new alert has age 0")

  M.setTime(130)
  m:beginCycle()
  c:add(5, { gen = "t1" })
  m:alert("lsc-low", "bad", "LSC below 10%")
  m:alert("t1-fuel", "warn", "Turbine 1 low on fuel")
  snap = m:snapshot()
  check(#snap.samples == 1 and snap.samples[1][1] == "power_eu_generated_total" and snap.samples[1][2] == 15,
    "beginCycle drops gauge series; counters keep their totals")
  check(snap.health == "bad" and snap.alerts[1].age == 30 and snap.alerts[1].level == "bad"
    and snap.alerts[2].id == "t1-fuel" and snap.alerts[2].age == 0,
    "an alert raised again keeps its age; levels and text update")

  M.setTime(140)
  m:beginCycle()
  m:health("bad")
  snap = m:snapshot()
  check(#snap.alerts == 0 and snap.health == "bad", "beginCycle clears alerts; health can be set directly")
  M.setTime(150)
  m:beginCycle()
  m:alert("lsc-low", "warn", "again")
  snap = m:snapshot()
  check(snap.health == "warn" and snap.alerts[1].age == 0,
    "beginCycle clears the health override; an alert that skipped a cycle starts over")

  check(raises(function() m:alert("x", "info", "t") end, "warn or bad"), "alert levels are warn or bad")
  check(raises(function() m:health("stale") end, "ok, warn or bad"), "stale is the hub's to set")
  m:alert("long", "warn", string.rep("a", 79) .. "é")
  local text = m:snapshot().alerts[2].text
  check(#text == 79, "alert text is cut to 80 bytes without splitting a character")
end

---------------------------------------------------------------- codec: one-packet messages
local function decodeAll(packets, token)
  local out = {}
  for i, p in ipairs(packets) do out[i] = assert(codec.decode(p, token)) end
  return out
end

do
  local enc = codec.encoder{ node = "prism-ore", role = "prism", boot = 81723, interval = 10, version = "0.7.0" }
  local m = metrics.new{ role = "prism", clock = clock }
  m:gauge("prism_backlog_items", "backlog", "items"):set(4200, { process = "ore" })
  m:alert("down:mac2", "warn", "mac2 stopped")

  local d = decodeAll(enc:describe(m:describe()))
  check(#d == 1 and d[1].kind == "describe" and d[1].seq == 1 and d[1].sid == 1 and d[1].parts == 1
    and d[1].metrics.prism_backlog_items.type == "gauge", "a small describe is one packet")
  local s = decodeAll(enc:snapshot(m:snapshot()))
  check(#s == 1, "a small snapshot is one packet")
  local msg = s[1]
  check(msg.proto == "lens/1" and msg.kind == "snapshot" and msg.node == "prism-ore" and msg.role == "prism"
    and msg.boot == 81723 and msg.seq == 2 and msg.sid == 2 and msg.part == 1 and msg.parts == 1
    and msg.version == "0.7.0", "the envelope carries proto, kind, node, role, boot, seq and version")
  check(msg.interval == 10 and msg.health == "warn" and msg.dseq == 1 and msg.alerts[1].id == "down:mac2"
    and msg.samples[1][1] == "prism_backlog_items" and msg.samples[1][3].process == "ore",
    "the snapshot carries interval, health, dseq, alerts and samples")
  check(msg.token == nil, "no token configured: none sent")

  local h = decodeAll(enc:hello())
  check(h[1].kind == "hello" and h[1].seq == 3, "hello is an envelope with the next seq")
end

---------------------------------------------------------------- codec: decoding
do
  local enc = codec.encoder{ node = "a", role = "power", boot = 1, token = "s3cret" }
  local data = enc:hello()[1]
  check(codec.decode(data, "s3cret").kind == "hello", "matching token: accepted")
  check(select(2, codec.decode(data, "other")) == "token", "wrong token: dropped")
  local open = codec.encoder{ node = "a", role = "power", boot = 1 }:hello()[1]
  check(select(2, codec.decode(open, "s3cret")) == "token", "token configured, none sent: dropped")
  check(codec.decode(data) ~= nil, "no token configured on the receiver: accepted")
  check(select(2, codec.decode("{{{")) == "garbled" and select(2, codec.decode(42)) == "garbled", "garbage is dropped")
  check(select(2, codec.decode(ser.serialize({ proto = "lens/2", kind = "hello", node = "a", boot = 1, seq = 1 })))
    == "proto", "another major version is dropped")
  check(select(2, codec.decode(ser.serialize({ proto = "lens/1", kind = "command", node = "a", boot = 1, seq = 1 })))
    == "kind", "unknown kinds are dropped")
  check(select(2, codec.decode(ser.serialize({ proto = "lens/1", kind = "snapshot", node = "a", boot = 1.5, seq = 1 })))
    == "envelope", "boot must be an integer")
  check(select(2, codec.decode(ser.serialize({ proto = "lens/1", kind = "snapshot", node = "a", boot = 1, seq = 1,
    part = 1, parts = 2 }))) == "envelope", "a multi-part message needs a sid")
  check(codec.decode(ser.serialize({ proto = "lens/1", kind = "hello", node = "a", boot = 1, seq = 1, extra = { 1 } }))
    ~= nil, "unknown fields are ignored")
end

---------------------------------------------------------------- codec: splitting and joining
local function bigSnapshot(n)
  local m = metrics.new{ role = "prism", clock = clock }
  local g = m:gauge("prism_machine_state", "state")
  for i = 1, n do
    for _, st in ipairs({ "running", "idle", "down" }) do
      g:set(st == "running" and 1 or 0, { process = "process" .. (i % 7), machine = "machine" .. i, state = st })
    end
  end
  m:alert("a", "warn", "something")
  return m:snapshot()
end

local function shuffled(list, seed)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  math.randomseed(seed)
  for i = #out, 2, -1 do
    local j = math.random(i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

do
  local snap = bigSnapshot(150)
  local enc = codec.encoder{ node = "prism-ore", role = "prism", boot = 5, interval = 10 }
  local packets = enc:snapshot(snap)
  local fits = true
  for _, p in ipairs(packets) do if #p > codec.LIMIT then fits = false end end
  check(#packets > 3 and fits, ("a big snapshot is split into packets of at most 7 KB (%d packets)"):format(#packets))

  local msgs = decodeAll(packets)
  local headOnly = true
  for i, msg in ipairs(msgs) do
    if msg.sid ~= msgs[1].seq or msg.part ~= i or msg.parts ~= #msgs or msg.seq ~= msgs[1].seq + i - 1 then headOnly = false end
    if i > 1 and (msg.health or msg.alerts or msg.interval or msg.dseq) then headOnly = false end
  end
  check(headOnly, "parts share the sid of the first; only part 1 carries health, alerts, interval and dseq")

  local asm = codec.assembler()
  local whole
  for i, msg in ipairs(shuffled(msgs, 7)) do
    local r = asm:add(msg, 0)
    if i < #msgs then check(r == nil, "part " .. i .. " of " .. #msgs .. " arrived: nothing yet") else whole = r end
  end
  local same = whole and #whole.samples == #snap.samples
  for i = 1, #snap.samples do
    local a, b = whole.samples[i], snap.samples[i]
    if not (a and a[1] == b[1] and a[2] == b[2] and a[3].machine == b[3].machine and a[3].state == b[3].state) then
      same = false
    end
  end
  check(same and whole.health == "warn" and whole.alerts[1].id == "a" and whole.part == 1 and whole.parts == 1,
    "parts arriving in any order join back into the original snapshot")
  check(asm:add(msgs[2], 1) == nil, "a late duplicate part of a finished snapshot does nothing")

  -- one part lost, then the next snapshot arrives whole
  local next1 = decodeAll(enc:snapshot(snap))
  for i = 1, #next1 - 1 do asm:add(next1[i], 2) end
  local next2 = decodeAll(enc:snapshot(snap))
  local got
  for _, msg in ipairs(next2) do got = asm:add(msg, 3) or got end
  check(got and got.sid == next2[1].sid, "a lost part costs one snapshot: the next one is applied")
  check(asm:add(next1[1], 4) == nil, "parts of an older snapshot are dropped")

  -- an incomplete snapshot expires after its interval
  local a2 = codec.assembler()
  local next3 = decodeAll(enc:snapshot(snap))
  for i = 1, #next3 - 1 do a2:add(next3[i], 100) end
  check(a2:add(next3[#next3], 111) == nil, "an incomplete snapshot is dropped interval seconds after its first part")

  -- a restart (new boot) starts over even though seq went back to 1
  local reboot = codec.encoder{ node = "prism-ore", role = "prism", boot = 6, interval = 10 }
  local r = decodeAll(reboot:snapshot({ health = "ok", dseq = 1, samples = {}, alerts = {} }))
  check(asm:add(r[1], 5) ~= nil and r[1].seq == 1, "a new boot is accepted even though its seq starts over")
end

do
  -- describe with many metrics
  local m = metrics.new{ role = "power", clock = clock }
  for i = 1, 120 do m:gauge(("power_gen%03d_eut"):format(i), "Output of generator " .. i .. " " .. string.rep("x", 40), "EU/t") end
  local enc = codec.encoder{ node = "power-main", role = "power", boot = 9 }
  local msgs = decodeAll(enc:describe(m:describe()))
  local asm = codec.assembler()
  local whole
  for _, msg in ipairs(shuffled(msgs, 3)) do whole = asm:add(msg, 0) or whole end
  local count = 0
  for _ in pairs(whole.metrics) do count = count + 1 end
  check(#msgs > 1 and count == 120 and whole.dseq == 120 and whole.metrics.power_gen042_eut.unit == "EU/t",
    "a big describe splits by metric and joins back")
end

do
  -- more alerts than fit: the worst are kept and the rest counted
  local m = metrics.new{ role = "prism", clock = clock }
  for i = 1, 150 do m:alert("warn" .. i, "warn", string.rep("w", 70)) end
  for i = 1, 5 do m:alert("bad" .. i, "bad", string.rep("b", 70)) end
  local enc = codec.encoder{ node = "n", role = "prism", boot = 1 }
  local packets = enc:snapshot(m:snapshot())
  local msg = codec.decode(packets[1])
  local bads = 0
  for _, a in ipairs(msg.alerts) do if a.level == "bad" then bads = bads + 1 end end
  check(#packets[1] <= codec.LIMIT and bads == 5 and msg.moreAlerts == 155 - #msg.alerts and msg.moreAlerts > 0,
    "too many alerts for a packet: the bad ones are kept and moreAlerts counts the rest")
end

do
  local enc = codec.encoder{ node = "n", role = "prism", boot = 1 }
  local huge = { health = "ok", dseq = 1, alerts = {}, samples = { { "prism_x", 1, { a = string.rep("z", 8000) } } } }
  check(raises(function() enc:snapshot(huge) end, "larger than a packet"), "one sample bigger than a packet is an error")
end

---------------------------------------------------------------- codec: numbers from OpenComputers
do
  local b = codec.newBoot()
  check(math.type(b) == "integer" and b >= 1 and b <= 0x7fffffff,
    "newBoot gives an integer even though math.random(m, n) doesn't in OpenComputers")
  check(math.type(math.random(1, 10)) == "float", "(the mock's math.random(m, n) is a float, like the game's)")
  local enc = codec.encoder{ node = "n", role = "prism", boot = 1234.0 }
  local msg = codec.decode(enc:hello()[1])
  check(msg and math.type(msg.boot) == "integer" and msg.boot == 1234, "a whole-number float boot is taken as an integer")
  check(raises(function() codec.encoder{ node = "n", role = "prism", boot = 1.5 } end, "whole-number boot"),
    "a boot that isn't a whole number is refused")
  local floaty = codec.decode(ser.serialize({ proto = "lens/1", kind = "snapshot", node = "a", boot = 7.0, seq = 3.0,
    sid = 2.0, part = 2.0, parts = 2.0, samples = {} }))
  check(floaty and math.type(floaty.boot) == "integer" and math.type(floaty.seq) == "integer"
    and math.type(floaty.part) == "integer" and floaty.sid == 2, "decode turns whole-number floats in the envelope into integers")
end

---------------------------------------------------------------- splash
do
  local splash = require("lens.splash")
  local Gui = require("lens.gui")
  local artOk = #splash.ART == 23
  for _, row in ipairs(splash.ART) do artOk = artOk and #row == 25 and not row:find("[^.WOBG]") end
  check(artOk, "splash: the logo is 25 x 23 pixels of known colors")
  local function width(runs) local n = 0; for _, r in ipairs(runs) do n = n + utf8.len(r[2]) end; return n end
  local small, big = splash.rows(1), splash.rows(2)
  check(#small == 12 and width(small[1]) == 25 and #big == 23 and width(big[1]) == 50, "splash: 25 x 12 cells, or 50 x 23 doubled")
  local gpu = require("component").gpu
  for _, size in ipairs({ { 160, 50, "splash" }, { 80, 25, "splash-tier2" } }) do
    M.resize(size[1], size[2])
    splash.show(gpu, size[1], size[2], "LENS", "9.9.9", Gui.C.accent)
    H.screen(size[3])
    local nx, ny = M.find("LENS  v9.9.9")
    check(M.find("S P E C T R A") and nx and M.fgAt(nx, ny) == Gui.C.accent,
      "splash: " .. size[1] .. "x" .. size[2] .. " shows the logo, SPECTRA and the name in LENS's color")
  end
  M.resize(160, 50)
end

H.done()
