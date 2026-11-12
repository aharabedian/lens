-- test_huds.lua: a HUD per Glasses Terminal, each showing its wearer's own settings (lens.hub.huds), and the
-- dashboard's HUD editor: opened by a tap, changing only the tapping player's HUD, saved to lens-hud.cfg,
-- closing by itself. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local huds = require("lens.hub.huds")
local config = require("lens.hub.config")
local glassesMock = require("glasses")

local function terminal(bound)
  local G = glassesMock.new()
  G.proxy.getBindPlayers = function() return bound end
  return G
end
local function evaluate(bars)
  local out = {}
  for i, b in ipairs(bars) do out[i] = { label = b.label, text = "1", frac = 0.5 } end
  return out
end
local MODEL = { now = 1, health = "ok", alerts = {}, nodes = {}, panels = {} }

---------------------------------------------------------------- lens.hub.huds
local cfg = assert(config.check({
  panels = { { label = "Power", value = "1" }, { label = "Ore", value = "2" }, { label = "Smelt", value = "3" } },
  hud = { bars = { { label = "Ore", value = "sum(x)", max = 10 } } },
}))
local path = H.TMP .. "/lens-hud.cfg"
local A, B, C = terminal("Aaron"), terminal({}), terminal({ "Aaron", "Bob" })
local hs = huds.new({ ["gl-a"] = A.proxy, ["gl-b"] = B.proxy, ["gl-c"] = C.proxy }, cfg.hud, path)

local cat = hs:catalog(cfg.panels)
check(#cat == 3 and cat[1].label == "Ore" and cat[1].max == 10 and cat[2].label == "Power" and cat[3].label == "Smelt",
  "the catalog: hud.bars first, then panels with other labels")
local s = hs:settings("Bob")
check(not s.own and s.anchor == "top-right" and s.scale == 1 and s.width == 160 and s.alerts == 3
  and #s.bars == 1 and s.bars[1] == "Ore", "a player without settings gets lens-hub.cfg's hud")
check(hs:wearing("Aaron") == 1 and hs:wearing("Bob") == 0,
  "at start a terminal's wearer comes from getBindPlayers, only when it names exactly one player")

hs:draw(MODEL, evaluate, cfg.panels)
check(A.find("Ore") and B.find("Ore") and C.find("Ore") and not A.find("Power"), "every terminal draws the defaults")

check(hs:change("Bob", function(x) x.bars = { "Power", "Smelt" }; x.anchor = "top-left"; x.scale = 1.5 end),
  "a change is saved")
hs:onGlasses("gl-b", "Bob", 1000, 500)
hs:draw(MODEL, evaluate, cfg.panels)
local pw, sm = B.find("Power"), B.find("Smelt")
check(pw and sm and pw.y < sm.y and not B.find("Ore") and pw.scale == 1.5 and B.live()[1].x == 4,
  "Bob's terminal: his bars, in his order, his size and corner")
check(A.find("Ore") and not A.find("Power") and A.live()[1].x == 854 - 4 - 160, "Aaron's terminal: unchanged")

hs:onGlasses("gl-a", "Aaron", 1200, 600)
hs:draw(MODEL, evaluate, cfg.panels)
check(A.live()[1].x == 1200 - 4 - 160 and B.live()[1].x == 4, "each terminal is placed by its own wearer's GUI size")

local f = io.open(path); local saved1 = f:read("*a"); f:close()
check(saved1:find('["Bob"] = { anchor = "top-left", scale = 1.5, width = 160, alerts = 3, bars = { "Power", "Smelt" } }', 1, true),
  "lens-hud.cfg: readable, one line per player")
local again = huds.new({ ["gl-b"] = B.proxy }, cfg.hud, path)
s = again:settings("Bob")
check(s.own and s.anchor == "top-left" and s.bars[2] == "Smelt", "settings come back after a restart")

f = io.open(path, "w")
f:write('return { Bob = { anchor = "middle", scale = 99, width = 200, bars = { "Power", 7 } }, [3] = {} }')
f:close()
s = huds.new({}, cfg.hud, path):settings("Bob")
check(s.anchor == "top-right" and s.scale == 1 and s.width == 200 and #s.bars == 1, "bad values in the file are ignored")

check(hs:reset("Bob") and not hs:settings("Bob").own, "back to the defaults")
hs:draw(MODEL, evaluate, cfg.panels)
check(B.find("Ore") and not B.find("Power"), "and the terminal shows them")

hs:change("Bob", function(x) x.bars = { "Gone", "Smelt" } end)
hs:draw(MODEL, evaluate, cfg.panels)
check(B.find("Smelt") and not B.find("Gone"), "a bar whose panel was removed is skipped")

local D, E = terminal({}), terminal({})
D.proxy.addRect = function() error("terminal unloaded") end
local hs2 = huds.new({ ["gl-d"] = D.proxy, ["gl-e"] = E.proxy }, cfg.hud, nil)
hs2:draw(MODEL, evaluate, cfg.panels)
check(hs2.error and hs2.error:find("terminal unloaded", 1, true) and E.find("Ore"), "a broken terminal doesn't stop the others")

---------------------------------------------------------------- the editor, in lens-hub
local net = require("net")
local codec = require("lens.codec")
local metrics = require("lens.metrics")

local function runHub(terms, cfgText, script)
  M.components = {}
  for addr, G in pairs(terms) do M.components[addr] = { type = "glasses", proxy = G.proxy, methods = {} } end
  local cfgPath = H.TMP .. "/hub/lens-hub.cfg"
  os.execute('mkdir -p "' .. H.TMP .. '/hub"')
  local fh = assert(io.open(cfgPath, "w")); fh:write(cfgText); fh:close()
  local n = net.new()
  M.modem = n:endpoint("hub")
  local ag = n:endpoint("prism-ore")
  ag.open(4243)
  local m = metrics.new{ role = "prism", clock = function() return M.time end }
  local enc = codec.encoder{ node = "prism-ore", role = "prism", boot = 3, interval = 5 }
  m:gauge("prism_backlog_items", "b"):set(1240000)
  m:gauge("prism_machine_state", "s"):set(1, { state = "running", machine = "m1" })
  local nextPush = 0
  M.onPull = function()
    if M.time >= nextPush then
      for _, p in ipairs(enc:snapshot(m:snapshot())) do ag.broadcast(4243, p) end
      nextPush = M.time + 5
    end
    local ev = n.pop(M.modem)
    if ev then return ev end
    return script(M.time)
  end
  local realStderr, written = io.stderr, {}
  io.stderr = { write = function(_, x) written[#written + 1] = x end }
  local ok, err = pcall(H.run, "lens-hub.lua", cfgPath)
  io.stderr = realStderr
  M.onPull = nil
  M.components = {}
  return ok and #written == 0, err or table.concat(written), H.TMP .. "/hub/lens-hud.cfg"
end

local function tapText(text, player, minY)
  local x, y = M.find(text, minY)
  assert(x, "nothing on screen says " .. text)
  return { "touch", "screen", x + 1, y, 0, player }
end

M.setTime(0)
M.resize(160, 50)
local GA, GB = terminal("Aaron"), terminal({})
local HUB_CFG = [[return {
  panels = { { label = "Backlog", value = "sum(prism_backlog_items)", max = 2000000 },
             { label = "Running", value = "sum(prism_machine_state)" } },
  hud = { bars = { { label = "Ore", value = "sum(prism_backlog_items)", max = 2000000 } } },
}]]
local st = {}
local steps = {
  function() return { "glasses_on", "gl-b", "Bob", 1000, 500 } end,
  function() st.dashHud = M.find(" HUD ", 1) ~= nil; return tapText(" HUD ", "Bob", 1) end,
  function()
    st.editor = M.find("HUD for Bob", 1) ~= nil and M.find("BARS (1 shown)", 1) ~= nil and M.find("[✓] Ore", 1) ~= nil
    st.screen1 = true
    H.screen("hud-editor")
    return tapText("Backlog", "Aaron", 3)    -- someone else's tap: nothing
  end,
  function() st.locked = M.find("BARS (1 shown)", 1) ~= nil; return tapText("Backlog", "Bob", 3) end,
  function() st.toggled = M.find("BARS (2 shown)", 1) ~= nil and GB.find("Backl") ~= nil and not GA.find("Backl")
    return tapText("▲", "Bob", 3) end,
  function()
    local _, oy = M.find("[✓] Ore", 3)
    local _, by = M.find("[✓] Backlog", 3)
    st.moved = by and oy and by < oy and GB.find("Backl").y < GB.find("Ore").y
    return tapText("top-left", "Bob", 3)
  end,
  function() st.anchored = GB.live()[1].x == 4 and GA.live()[1].x == 854 - 164
    local x, y = M.find("Size", 3)
    return { "touch", "screen", x + 20, y, 0, "Bob" }   -- its +
  end,
  function() st.bigger = GB.find("Ore").scale == 1.25 and M.find(" 1.2", 3) ~= nil; return tapText("DONE", "Bob", 1) end,
  function() st.closed = M.find("NODES", 1) ~= nil; return tapText(" HUD ", "Aaron", 1) end,
  function() st.aaron = M.find("HUD for Aaron", 1) ~= nil and M.find("Showing on 1 terminal", 1) ~= nil; return nil end,
}
local i = 0
local ok, err, hudPath = runHub({ ["gl-a"] = GA, ["gl-b"] = GB }, HUB_CFG, function(t)
  if t < 3 then return nil end
  i = i + 1
  if steps[i] then return steps[i]() end
  if not st.timeout and t > 90 then st.timeout = M.find("NODES", 1) ~= nil; return { "interrupted" } end
  if t > 120 then return { "interrupted" } end
end)
check(ok, "lens-hub runs with two terminals" .. (ok and "" or (": " .. tostring(err))))
check(st.dashHud, "the dashboard has a HUD button when a terminal is attached")
check(st.editor, "tapping HUD opens the editor for whoever tapped, with the bars they see")
check(st.locked, "another player's taps change nothing")
check(st.toggled, "tapping a bar shows it on the tapper's own terminal only")
check(st.moved, "arrows order the bars, on screen and in the glasses")
check(st.anchored, "a corner moves only the tapper's HUD")
check(st.bigger, "size steps by 0.25")
check(st.closed, "DONE goes back to the dashboard")
check(st.aaron, "another player opens their own editor")
check(st.timeout, "the editor closes after a minute without a tap")
local fh = io.open(hudPath); local saved = fh and fh:read("*a") or ""; if fh then fh:close() end
check(saved:find('["Bob"] = { anchor = "top-left", scale = 1.25', 1, true) and saved:find('bars = { "Backlog", "Ore" }', 1, true)
  and not saved:find("Aaron", 1, true), "Bob's settings are saved in lens-hud.cfg next to the config; Aaron has none")

-- Tier 2: the editor fits.
M.setTime(0)
M.resize(80, 25)
M.oob = 0
local opened
ok = runHub({ ["gl-a"] = terminal("Aaron") }, HUB_CFG, function(t)
  if t < 3 then return nil end
  if not opened then opened = true; return tapText(" HUD ", "Aaron", 1) end
  H.screen("hud-editor-tier2")
  return { "interrupted" }
end)
check(ok and M.oob == 0 and M.find("HUD for Aaron", 1) and M.find("bottom-right", 1) and M.find("Alerts", 1),
  "on a tier 2 screen the editor fits")
M.resize(160, 50)

H.done()
