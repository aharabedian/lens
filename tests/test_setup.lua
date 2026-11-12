-- test_setup.lua: lens-setup with scripted answers: a first run that finds a PRISM router on the simulated
-- network and adds its panels and a HUD bar, the file it writes (loads, comments, lens-hub runs it), .shrc,
-- a re-run that keeps everything and only offers new agents, PRISM's port refused, no agents, no network
-- card, no glasses, cancelling, declining, and a broken existing config.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local net = require("net")
local codec = require("lens.codec")
local metrics = require("lens.metrics")
local config = require("lens.hub.config")
local files = require("lens.files")

local prefix = H.TMP .. "/root"
local home = prefix .. "/home"
os.execute('mkdir -p "' .. home .. '"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LENS_PREFIX" then return prefix end return realGetenv(k) end
local CFG, SHRC = home .. "/lens-hub.cfg", home .. "/.shrc"

-- The world: a PRISM router reporting to LENS (answers hello), on the simulated network.
local n
local agents = {}
local function agent(node, role, withMachines, token)
  local ep = n:endpoint(node)
  ep.open(4243)
  local m = metrics.new{ role = role, clock = function() return M.time end }
  if role == "prism" then
    m:gauge("prism_backlog_items", "b"):set(10, { process = "ore" })
    if withMachines then m:gauge("prism_machine_state", "s"):set(1, { machine = "m1", state = "running" }) end
  else
    m:gauge(role .. "_eu_stored", "e"):set(5)
  end
  local enc = codec.encoder{ node = node, role = role, boot = 1, token = token }
  agents[#agents + 1] = function()
    local ev = n.pop(ep)
    while ev do
      local msg = codec.decode(ev[6], token)
      if msg and msg.kind == "hello" then
        for _, p in ipairs(enc:describe(m:describe())) do ep.broadcast(4243, p) end
        for _, p in ipairs(enc:snapshot(m:snapshot())) do ep.broadcast(4243, p) end
      end
      ev = n.pop(ep)
    end
  end
end

local function world(o)
  o = o or {}
  n = net.new()
  agents = {}
  if o.noModem then M.modem = nil else M.modem = n:endpoint("hub") end
  M.components = o.glasses and { ["gl000000-0000"] = { type = "glasses", proxy = {}, methods = {} } } or {}
  for _, a in ipairs(o.agents or {}) do agent(table.unpack(a)) end
  M.onPull = function()
    for _, step in ipairs(agents) do step() end
    if M.modem then
      local ev = n.pop(M.modem)
      if ev then return ev end
    end
  end
end

-- Run lens-setup with scripted answers; returns everything it printed or prompted.
local function setup(answers)
  local out = {}
  local realPrint, realWrite, realRead = print, io.write, io.read
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(parts, "\t") .. "\n"
  end
  io.write = function(...) for _, s in ipairs({ ... }) do out[#out + 1] = tostring(s) end end
  local i = 0
  io.read = function() i = i + 1; return answers[i] end   -- nil after the last answer = Ctrl+D
  local ok, err = pcall(H.run, "lens-setup.lua")
  print, io.write, io.read = realPrint, realWrite, realRead
  M.onPull = nil
  return table.concat(out), ok, err
end
local out
local function has(s) return out:find(s, 1, true) ~= nil end

---------------------------------------------------------------- first run
local f = assert(io.open(SHRC, "w")); f:write("echo hello\nprism\n"); f:close()
world({ glasses = true, agents = { { "prism-ore", "prism", true }, { "power-main", "power" } } })
M.setTime(0)
out = setup({
  "",            -- name: hub
  "4242", "",    -- PRISM's port refused, then the default 4243
  "",            -- no secret
  "",            -- add panels for prism-ore: yes
  "",            -- HUD: yes
  "",            -- corner: top right
  "",            -- prism-ore's bar: machines running
  "",            -- start on boot: yes
  "",            -- save: yes
})
check(has("4242 is PRISM's control-screen port"), "PRISM's control port is refused")
check(has("found power-main (power)") and has("found prism-ore (prism)"), "lists the agents that answer the hello")
check(has("add panels for prism-ore (ore backlog, ore machines, ore down)?"), "offers a PRISM router's standard panels")
check(has("no standard panels for power agents yet"), "says when a kind of agent has no standard panels")
check(has("1) machines running") and has("1) top right"), "HUD: a corner, and a bar per router")
check(has("This will be saved to " .. CFG) and has("saved 3 panel(s) and 1 HUD bar(s)"), "shows the file, then saves it")
local text = files.read(CFG)
check(text:find("-- lens-hub.cfg - written by lens-setup", 1, true)
  and text:find("port = 4243,%s+%-%- the LENS port") ~= nil, "the file is commented")
check(text:find([[value = 'sum(prism_backlog_items{node="prism-ore"})']], 1, true) ~= nil,
  "queries are written in single quotes, readable")
local c = assert(config.load(CFG))
check(c.node == "hub" and c.port == 4243 and c.token == nil and #c.panels == 3 and c.panels[2].of
  and c.hud.anchor == "top-right" and #c.hud.bars == 1 and c.hud.bars[1].label == "ore", "the saved config loads and checks")
check(files.read(SHRC) == "echo hello\nprism\nlens-hub\n", "start on boot adds lens-hub to .shrc and keeps the rest")
check(not files.exists(CFG .. ".bak"), "no .bak on the first save")

-- lens-hub runs the result
local G = require("glasses").new()
world({ agents = { { "prism-ore", "prism", true } } })
M.components = { ["gl000000-0000"] = { type = "glasses", proxy = G.proxy, methods = {} } }
local prevPull, seen = M.onPull, {}
M.onPull = function(k)
  local ev = prevPull(k)
  if ev then return ev end
  if M.time > 8 then
    seen.panel, seen.bar = M.find("ore backlog") ~= nil, G.find("1/1") ~= nil
    return { "interrupted" }
  end
end
local okHub = pcall(H.run, "lens-hub.lua", CFG)
M.onPull = nil
check(okHub and seen.panel and seen.bar, "lens-hub runs the saved config: panels and the HUD bar")

---------------------------------------------------------------- re-run: keeps everything, offers only new agents
local edited = files.read(CFG):gsub("staleAfter = 3", "staleAfter = 5")
f = assert(io.open(CFG, "w")); f:write(edited); f:close()
world({ glasses = true, agents = { { "prism-ore", "prism", true }, { "prism-smelt", "prism", false } } })
out = setup({ "", "", "", "", "", "", "", "", "", "" })   -- ..., smelt's bar: backlog, full at 10000, ...
check(has("[hub]") and has("[4243]") and not has("add panels for prism-ore"),
  "re-run: answers are the defaults, and agents with panels aren't offered again")
check(has("add panels for prism-smelt (smelt backlog)?"), "a router without machines gets just a backlog panel")
check(has("1) backlog (a bar against a size you pick)"), "and a backlog bar (no machines to count)")
c = assert(config.load(CFG))
check(#c.panels == 4 and c.staleAfter == 5 and #c.hud.bars == 2 and c.hud.bars[2].max == 10000
  and c.hud.bars[2].badAbove == 9000, "new panels and bars are added; hand edits are kept")
check(files.exists(CFG .. ".bak") and files.read(CFG .. ".bak"):find("staleAfter = 5", 1, true),
  "the previous file is kept as .bak")
check(files.read(SHRC) == "echo hello\nprism\nlens-hub\n", ".shrc unchanged when start on boot didn't change")

---------------------------------------------------------------- a secret, no agents, no glasses, boot off
world({ agents = { { "prism-ore", "prism", true, "other" } } })
out = setup({ "", "", "s3cret", "n", "", "" })
check(has("no agents answered") and has("lensToken"), "no agents (the router has another secret): says how to connect them")
check(has("no Glasses Terminal attached: skipped (hud settings are kept)"), "no glasses: the HUD step is skipped")
c = assert(config.load(CFG))
check(c.token == "s3cret" and #c.hud.bars == 2, "the secret is saved; HUD settings kept")
check(files.read(SHRC) == "echo hello\nprism\n", "start on boot off removes the lens-hub line")

---------------------------------------------------------------- no network card
world({ noModem = true })
out = setup({ "", "", "", "", "" })
check(has("no network card: can't look for agents"), "no network card: setup still works, without discovery")

---------------------------------------------------------------- cancelling, declining, a broken file
local before = files.read(CFG)
world({})
out = setup({ "", "" })
check(has("cancelled - nothing saved") and files.read(CFG) == before, "Ctrl+D cancels without saving")
world({})
out = setup({ "", "", "", "", "n" })   -- name, port, secret, boot, then n
check(has("nothing saved") and files.read(CFG) == before, "answering n at the end saves nothing")
f = assert(io.open(CFG, "w")); f:write("return {"); f:close()
world({})
local _, ok, err = setup({})
check(not ok and tostring(err):find("can't be read", 1, true), "a config that doesn't load is reported, not overwritten")

H.done()
