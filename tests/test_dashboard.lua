-- test_dashboard.lua: lens-hub end to end on the mock screen, with a PRISM-like agent on the simulated
-- network: zero-config start, finding agents with hello, nodes, panels (bars, of, thresholds), alerts and
-- acking them by touch, a node going stale (beep once), redrawing only what changed, QUIT, a tier 2
-- screen, and config errors.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local codec = require("lens.codec")
local metrics = require("lens.metrics")
local net = require("net")

local PORT = 4243

---------------------------------------------------------------- an agent like PRISM's exporter
local function newAgent(n, node, machines)
  local ag = { modem = n:endpoint(node), silent = false, nextPush = 0, backlog = 4200, down = {} }
  ag.m = metrics.new{ role = "prism", clock = function() return M.time end }
  ag.enc = codec.encoder{ node = node, role = "prism", boot = 11, interval = 5 }
  ag.modem.open(PORT)
  local state = ag.m:gauge("prism_machine_state", "state")
  local backlog = ag.m:gauge("prism_backlog_items", "backlog", "items")
  local function send(packets) for _, p in ipairs(packets) do ag.modem.broadcast(PORT, p) end end
  local function cycle()
    ag.m:beginCycle()
    backlog:set(ag.backlog, { process = "ore" })
    for i = 1, machines do
      local name = "mac" .. i
      local st = ag.down[name] and "down" or "running"
      for _, s in ipairs({ "running", "idle", "down" }) do
        state:set(s == st and 1 or 0, { process = "ore", machine = name, state = s })
      end
      if ag.down[name] then ag.m:alert("machine:" .. name, "bad", name .. ": no power") end
    end
  end
  function ag.step(now)
    local ev = n.pop(ag.modem)
    while ev do
      local msg = codec.decode(ev[6])
      if msg and msg.kind == "hello" and not ag.silent then cycle(); send(ag.enc:describe(ag.m:describe())); send(ag.enc:snapshot(ag.m:snapshot())) end
      ev = n.pop(ag.modem)
    end
    if not ag.silent and now >= ag.nextPush then
      cycle()
      send(ag.enc:snapshot(ag.m:snapshot()))
      ag.nextPush = now + 5
    end
  end
  return ag
end

local function cfgFile(name, text)
  local path = H.TMP .. "/" .. name .. ".cfg"
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
  return path
end

local function tapText(text, minY)
  local x, y = M.find(text, minY)
  assert(x, "nothing on screen says " .. text)
  return { "touch", "screen", x, y, 0, "player" }
end

local function run(n, hubModem, agents, cfgPath, script)
  M.modem = hubModem
  M.onPull = function()
    for _, ag in ipairs(agents) do ag.step(M.time) end
    local ev = n.pop(hubModem)
    if ev then return ev end
    return script(M.time)
  end
  -- The program catches errors in its loop and writes them to stderr: count those as failures too.
  local realStderr, written = io.stderr, {}
  io.stderr = { write = function(_, ...) for _, s in ipairs({ ... }) do written[#written + 1] = tostring(s) end end }
  local ok, err = pcall(H.run, "lens-hub.lua", cfgPath)
  io.stderr = realStderr
  M.onPull = nil
  if ok and #written > 0 then return false, table.concat(written) end
  return ok, err
end

---------------------------------------------------------------- no config, no agents
do
  M.setTime(0)
  local n = net.new()
  local hubModem = n:endpoint("hub")
  local seen = {}
  local slept = M.slept
  local ok, err = run(n, hubModem, {}, H.TMP .. "/missing.cfg", function(t)
    if t >= 3 and not seen.first then
      seen.first = true
      seen.header = M.row(1)
      seen.waiting = M.find("Waiting for agents on port 4243") ~= nil
      seen.noPanels = M.find("No panels yet: run lens-setup") ~= nil
      seen.quiet = M.find("All quiet.") ~= nil
      H.screen("dashboard-empty")
      return tapText(" QUIT ")
    end
    if t > 10 then return { "interrupted" } end
  end)
  check(ok, "lens-hub runs without a config file" .. (ok and "" or (": " .. tostring(err))))
  check(M.slept - slept == require("lens.splash").SECONDS, "the SPECTRA logo shows while lens-hub starts")
  check(not seen.header:find("▀", 1, true), "the first screen replaces the logo")
  check(seen.header:find("LENS", 1, true) and seen.header:find(" OK ", 1, true) and seen.header:find("0 nodes", 1, true)
    and seen.header:find("v" .. require("lens.version"), 1, true), "header: LENS, health OK, no nodes, the version")
  check(seen.waiting and seen.noPanels and seen.quiet, "an empty hub says it's waiting, how to add panels, and all quiet")
  check(M.time < 10, "QUIT stops the hub")
  local hello = codec.decode(n.sent[1].data[1])
  check(hello and hello.kind == "hello" and n.sent[1].port == PORT, "the hub says hello on its port at start")
end

---------------------------------------------------------------- the example config, a PRISM agent
local exampleCfg = H.ROOT .. "/config/lens-hub.example.cfg"
do
  M.setTime(0)
  M.beeps = 0
  local n = net.new()
  local hubModem = n:endpoint("hub")
  local ore = newAgent(n, "prism-ore", 2)
  ore.silent = true                       -- starts after the hub: only the hub's hello brings it in
  local s = {}
  local ok, err = run(n, hubModem, { ore }, exampleCfg, function(t)
    if t >= 1 and not s.wake then
      s.wake = true
      ore.silent = false
      ore.modem.broadcast(PORT, "not lens")                      -- noise on the port is ignored
      return { "modem_message", "hub", "prism-ore", 4242, 0, "wrong port" }
    end
    if t >= 4 and not s.panels then
      s.panels = true
      s.node = M.find("prism-ore") ~= nil and M.find("prism", select(2, M.find("prism-ore")), 25) ~= nil
      s.backlog = M.find("4.2k items") ~= nil
      s.running = M.find("2/2") ~= nil
      local _, by = M.find("Ore backlog")
      s.barCells = 0
      for x = 1, M.W do if M.bgAt(x, by + 1) == require("lens.gui").C.info then s.barCells = s.barCells + 1 end end
      s.quiet = M.find("All quiet.") ~= nil
      H.screen("dashboard-running")
      ore.down.mac2 = true
      ore.backlog = 9500
      return nil
    end
    if t >= 11 and not s.alert then
      s.alert = true
      s.alertRow = M.find("mac2: no power") ~= nil
      s.header = M.row(1)
      s.beeps = M.beeps
      local bx = M.find("9.5k items")
      s.badColor = bx and M.fgAt(bx, select(2, M.find("9.5k items"))) == require("lens.gui").C.bad
      s.downText = M.find("1/2") ~= nil
      H.screen("dashboard-alert")
      return tapText("mac2: no power")
    end
    if s.alert and not s.acked then
      s.acked = true
      s.ackedRow = M.find("✓ mac2: no power") ~= nil
      -- nothing changes for a few seconds: count GPU calls per tick
      s.calls = M.gpuCalls
      s.callsAt = t
      return nil
    end
    if s.acked and not s.quietTick and t >= s.callsAt + 3 then
      s.quietTick = true
      s.perTick = (M.gpuCalls - s.calls) / 3
      ore.silent = true                    -- the agent stops reporting
      return nil
    end
    if s.quietTick and t >= 30 and not s.stale then
      s.stale = true
      s.staleRow = M.find("prism-ore stopped reporting") ~= nil
      s.staleNode = M.find("STALE", 3) ~= nil
      s.staleBeeps = M.beeps
      s.header2 = M.row(1)
      H.screen("dashboard-stale")
      return tapText(" ACK ALL ")
    end
    if s.stale and not s.ackAll then
      s.ackAll = true
      s.allAcked = M.find("✓ prism-ore stopped reporting") ~= nil
      s.ackAllGone = M.find(" ACK ALL ") == nil
      return nil
    end
    if s.ackAll and t >= 40 then
      s.endBeeps = M.beeps
      return { "interrupted" }
    end
  end)
  check(ok, "lens-hub runs with the example config" .. (ok and "" or (": " .. tostring(err))))
  check(s.node, "an agent that starts later answers the hub's hello and is listed with its role")
  check(s.backlog and s.running, "panels: backlog with its unit, machines running as value/of")
  check(s.barCells > 10, "a panel with max draws a bar")
  check(s.quiet, "no alerts yet")
  check(s.alertRow and s.header:find(" BAD ", 1, true) and s.header:find("alerts: 1 bad", 1, true),
    "an agent's bad alert is listed, and the header turns BAD")
  check(s.beeps == 1, "a new bad alert beeps once")
  check(s.badColor, "a value past badAbove is drawn red")
  check(s.downText, "the running panel follows machine states")
  check(s.ackedRow, "tapping an alert acknowledges it")
  check(s.perTick < 12, ("a quiet tick redraws only what changed (%.1f GPU calls per second)"):format(s.perTick))
  check(s.staleRow and s.staleNode and s.header2:find(" BAD ", 1, true),
    "an agent that stops reporting shows STALE, with an alert")
  check(s.staleBeeps == 2, "and beeps again (new bad alert)")
  check(s.allAcked and s.ackAllGone, "ACK ALL acknowledges every alert and then hides itself")
  check(s.endBeeps == 2, "acknowledged alerts don't beep again")
  check(M.oob == 0, "nothing drawn off screen" .. (M.oobAt and (": " .. M.oobAt) or ""))
end

---------------------------------------------------------------- tier 2 screen
do
  M.resize(80, 25)
  M.setTime(100)
  local n = net.new()
  local hubModem = n:endpoint("hub")
  local ore = newAgent(n, "prism-ore", 3)
  local s = {}
  local ok, err = run(n, hubModem, { ore }, exampleCfg, function(t)
    if t >= 104 and not s.done then
      s.done = true
      s.panels = M.find("Ore backlog") ~= nil and M.find("3/3") ~= nil and M.find("Ore machines down") ~= nil
      s.nodes = M.find("NODES") ~= nil and M.find("prism-ore") ~= nil
      s.alerts = M.find("ALERTS (0)") ~= nil
      H.screen("dashboard-tier2")
      return { "interrupted" }
    end
  end)
  check(ok, "lens-hub runs on an 80x25 screen" .. (ok and "" or (": " .. tostring(err))))
  check(s.panels and s.nodes and s.alerts, "80x25: panels, then nodes, then alerts, stacked")
  check(M.oob == 0, "80x25: nothing drawn off screen" .. (M.oobAt and (": " .. M.oobAt) or ""))
  M.resize(160, 50)
end

---------------------------------------------------------------- config errors
do
  local n = net.new()
  local bad = cfgFile("bad-panel", [[return { panels = { { label = "Ore", value = "sum(prism_x" } } }]])
  local ok, err = run(n, n:endpoint("hub"), {}, bad, function() return { "interrupted" } end)
  check(not ok and tostring(err):find("panel 1 (Ore): value: expected )", 1, true),
    "a bad panel query stops the hub with the panel named")
  bad = cfgFile("bad-rule", [[return { rules = { { id = "x", when = "1", level = "loud" } } }]])
  ok, err = run(n, n:endpoint("hub"), {}, bad, function() return { "interrupted" } end)
  check(not ok and tostring(err):find("rule x: level must be warn or bad", 1, true), "a bad rule is named too")
  bad = cfgFile("bad-lua", "return {")
  ok, err = run(n, n:endpoint("hub"), {}, bad, function() return { "interrupted" } end)
  check(not ok and tostring(err):find("bad-lua.cfg", 1, true), "a config that isn't valid Lua says which file")
  ok, err = pcall(function()
    M.modem = nil
    H.run("lens-hub.lua", H.TMP .. "/missing.cfg")
  end)
  check(not ok and tostring(err):find("needs a network card", 1, true), "no network card: a clear error")
end

---------------------------------------------------------------- the screen's shape
-- resolution = "fit" (the default): a 3 wide, 4 tall screen gets 73 x 50, and the stacked layout uses the height.
do
  local R = require("hubrun")(H)
  local POWER = R.agent{ node = "power-room", role = "lumen", setup = function(m)
    m:gauge("lumen_fill_ratio", "f"):set(0.95)
  end }
  M.setTime(0)
  M.resize(73, 50)
  M.aspect = { 3, 4 }
  M.oob = 0
  local seen
  local ok = R.run{ cfg = 'return { panels = { { label = "Power", value = "lumen_fill_ratio", format = "percent" } } }',
    dir = "portrait", agents = { POWER }, script = function(t)
      if t < 12 then return nil end              -- a sparkline sample with data
      seen = M.find("PANELS", 1) and M.find("NODES", 1) and M.find("▁", 1) and M.find(" DATA ", 1) and M.find("QUIT", 1)
      H.screen("dashboard-portrait")
      return "stop"
    end }
  check(ok and M.resolution[1] == 73 and M.resolution[2] == 50, "resolution fit: 73 x 50 on a 3 x 4 screen")
  check(seen and M.oob == 0, "tall and narrow: panels with sparklines, then nodes and alerts; the header fits")
  M.aspect = nil
  M.resize(160, 50)
end

H.done()
