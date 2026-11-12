-- test_huds.lua: values formatted for display (lens.hub.format); HUD blocks with bar, text, alerts and gap
-- elements, placed from nine anchors; a HUD per Glasses Terminal with its wearer's settings
-- (lens.hub.huds); the dashboard's HUD editor (blocks, elements, anchors, nudges, only the tapping player);
-- and a resolution that fits the screen's shape. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local format = require("lens.hub.format")
local hud = require("lens.hub.hud")
local huds = require("lens.hub.huds")
local config = require("lens.hub.config")
local Gui = require("lens.gui")
local glassesMock = require("glasses")
local P = hud.COLORS

local function near(color, hex)
  local r, g, b = hud.rgb(hex, "float")
  return math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6 and math.abs(color[3] - b) < 1e-6
end
local function terminal(bound)
  local G = glassesMock.new()
  G.proxy.getBindPlayers = function() return bound end
  return G
end

---------------------------------------------------------------- format
local function fv(view, v, total) return { format.view(view, v, total) } end
check(fv({}, 1240000)[1] == "1.2M" and fv({ unit = "EU/t" }, 640)[1] == "640 EU/t" and fv({}, nil)[1] == "–",
  "auto: short numbers, the unit after")
local r = fv({ format = "percent" }, 0.953)
check(r[1] == "95%" and r[2] == 0.953, "percent: 0..1 as %, and the bar's fraction")
check(fv({ format = "duration" }, 7500)[1] == "2h 05m" and fv({ format = "duration" }, 45)[1] == "45s"
  and fv({ format = "duration" }, 3 * 86400 + 3600)[1] == "3d 1h", "duration: seconds read naturally")
r = fv({ format = "signed", unit = "EU/t", color = "sign" }, 2370)
check(r[1] == "+2.4k EU/t" and r[3] == "good", "signed: a + above zero; color sign: green")
r = fv({ format = "signed", unit = "EU/t", color = "sign" }, -2000)
check(r[1] == "-2k EU/t" and r[3] == "bad", "below zero: red")
check(fv({ color = "sign" }, 0)[3] == nil and fv({ color = "none", badAbove = 1 }, 5)[3] == nil, "zero, and none: no color")
check(fv({ badBelow = 0.1, warnBelow = 0.25 }, 0.2)[3] == "warn" and fv({ max = 10 }, 20)[2] == 1,
  "thresholds as before; a bar's fraction stops at 1")
check(fv({ of = "x", unit = "EU" }, 5e9, 1e10)[1] == "5G/10G EU" and fv({ of = "x" }, 5, 10)[2] == 0.5, "of: value/total")

---------------------------------------------------------------- config
local c = assert(config.check({ hud = { blocks = {
  { anchor = "top", elements = {
    { kind = "bar", label = "Power", value = "1", format = "percent" },
    { kind = "text", label = "Net 5m", value = "2", format = "signed", color = "sign" },
    { kind = "gap" }, { kind = "alerts" } } },
  { anchor = "bottom-left", x = 30, y = -60 },
} } }))
local b1, b2 = c.hud.blocks[1], c.hud.blocks[2]
check(b1.x == 0 and b1.y == 4 and b1.width == 160 and b1.elements[4].count == 3 and b2.x == 30 and b2.y == -60,
  "blocks: each anchor's default offset (4 in from its edges), width, alerts count")
c = assert(config.check({ hud = { anchor = "bottom-right", x = 10, y = 20, alerts = 2,
  bars = { { label = "Ore", value = "1", max = 5 } } } }))
b1 = c.hud.blocks[1]
check(#c.hud.blocks == 1 and b1.anchor == "bottom-right" and b1.x == -10 and b1.y == -20
  and b1.elements[1].kind == "bar" and b1.elements[1].label == "Ore" and b1.elements[2].count == 2,
  "the first form (corner, margins, bars, alerts) becomes one block")
local function err(t) local _, e = config.check(t); return e or "" end
check(err({ hud = { blocks = { { anchor = "middle" } } } }):find("anchor must be one of", 1, true), "anchors are checked")
check(err({ hud = { blocks = { { elements = { { kind = "dial" } } } } } }):find('kind must be "bar"', 1, true), "kinds are checked")
check(err({ panels = { { label = "x", value = "1", format = "hex" } } }):find("format must be", 1, true)
  and err({ panels = { { label = "x", value = "1", color = "red" } } }):find("color must be", 1, true), "format and color are checked")
check(assert(config.check({ panels = { { label = "x", value = "1", percent = true } } })).panels[1].format == "percent",
  "percent = true still works")
check(err({ resolution = "big" }):find("resolution must be", 1, true) and config.check({}).resolution == "fit",
  "resolution: fit by default, checked")

---------------------------------------------------------------- hud blocks
local MODEL = { now = 1, health = "ok", alerts = {}, nodes = {}, panels = {} }
local function blockModel(blocks, extra)
  local m = setmetatable({ hudBlocks = blocks, screen = { w = 800, h = 400 } }, { __index = MODEL })
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
do
  local G = glassesMock.new()
  local h = hud.new(G.proxy, { scale = 1, alpha = 0.35 })
  h:draw(blockModel({
    { anchor = "top", x = 0, y = 4, width = 160, items = {
      { kind = "bar", label = "Power", text = "95%", frac = 0.95 },
      { kind = "text", label = "Net 5m", text = "+2.4k EU/t", level = "good" },
      { kind = "gap" },
      { kind = "alerts", count = 2 } } },
    { anchor = "center", x = 0, y = 0, width = 120, items = { { kind = "text", label = "Ore", text = "1.2M" } } },
    { anchor = "bottom-right", x = -10, y = -10, width = 100, items = {} },
  }, { alerts = { { level = "bad", text = "Sifter down" }, { level = "warn", text = "two" }, { level = "warn", text = "three" } } }))
  H.glasses("hud-blocks", G)
  local live = G.live()
  local bg1 = live[1]
  check(bg1.x == 400 - 80 and bg1.y == 4, "top: centered across, 4 down")
  local value, label = G.find("+2.4k EU/t"), G.find("Net 5m")
  check(value and label and label.y == value.y and math.abs(value.x + G.textWidth(value) - (bg1.x + 158)) < 1
    and near(value.color, P.good) and near(label.color, P.dim), "text: dim label, the value right-aligned, green for good")
  local gapAfter = G.find("Sifter down")
  check(gapAfter and gapAfter.y - value.y == 11 + 5 and G.find("two") and not G.find("three") and G.find("+1 more"),
    "a gap is half a row; alerts show their count, then +N more")
  local ore = G.find("Ore")
  local bg2
  for _, s in ipairs(live) do if s.kind == "rect" and s.w == 120 then bg2 = s end end
  check(bg2 and bg2.x == 400 - 60 and math.abs((bg2.y + bg2.h / 2) - 200) <= 1 and ore.y > bg2.y,
    "center: in the middle of the view")
  local ok3 = G.find("LENS OK")
  check(ok3 and ok3.x > 800 - 100 - 10 and ok3.y > 300, "an empty block: LENS OK, in its corner")
  local calls = h.calls
  h:draw(blockModel({ { anchor = "top", x = 0, y = 4, width = 160, items = { { kind = "text", label = "Net 5m", text = "+2.4k EU/t" } } } }))
  check(not G.find("Sifter down") and not G.find("LENS OK") and not G.find("Power") and h.calls > calls,
    "blocks and elements that go away are hidden")
  h:draw(blockModel({ { anchor = "top-left", x = -500, y = 9000, width = 160, items = {} } }))
  local bg = G.live()[1]
  check(bg.x == 0 and bg.y + bg.h <= 400, "a block nudged off the view stays on it")
end

---------------------------------------------------------------- lens.hub.huds
local cfg = assert(config.check({
  panels = { { label = "Power", value = "1" }, { label = "Ore", value = "2" }, { label = "Smelt", value = "3" } },
  hud = { bars = { { label = "Ore", value = "sum(x)", max = 10 } } },
}))
local function evaluate(views)
  local out = {}
  for i, v in ipairs(views) do out[i] = { label = v.label, text = "v" .. v.label, frac = 0.5 } end
  return out
end
local path = H.TMP .. "/lens-hud.cfg"
local A, B, C = terminal("Aaron"), terminal({}), terminal({ "Aaron", "Bob" })
local hs = huds.new({ ["gl-a"] = A.proxy, ["gl-b"] = B.proxy, ["gl-c"] = C.proxy }, cfg.hud, path)

local cat = hs:catalog(cfg.panels)
check(#cat == 3 and cat[1].label == "Ore" and cat[1].max == 10 and cat[2].label == "Power" and cat[3].label == "Smelt",
  "the catalog: the default HUD's views first, then panels with other labels")
local s = hs:settings("Bob")
check(not s.own and #s.blocks == 1 and s.blocks[1].anchor == "top-right" and s.blocks[1].x == -4
  and s.blocks[1].elements[1].view == "Ore" and s.blocks[1].elements[2].kind == "alerts",
  "a player without settings gets lens-hub.cfg's hud, as blocks")
check(hs:wearing("Aaron") == 1 and hs:wearing("Bob") == 0,
  "at start a terminal's wearer comes from getBindPlayers, only when it names exactly one player")

hs:draw(MODEL, evaluate, cfg.panels)
check(A.find("vOre") and B.find("vOre") and C.find("vOre") and not A.find("Power"), "every terminal draws the defaults")

check(hs:change("Bob", function(x)
  x.scale = 1.5
  x.blocks = { { anchor = "top-left", x = 4, y = 4, width = 160,
      elements = { { kind = "bar", view = "Power" }, { kind = "text", view = "Smelt" } } },
    { anchor = "bottom", x = 0, y = -20, width = 120, elements = { { kind = "alerts", count = 1 } } } }
end), "a change is saved")
hs:onGlasses("gl-b", "Bob", 1000, 500)
hs:draw(MODEL, evaluate, cfg.panels)
local pw, sm = B.find("Power"), B.find("vSmelt")
check(pw and sm and pw.y < sm.y and not B.find("vOre") and pw.scale == 1.5 and B.live()[1].x == 4,
  "Bob's terminal: his blocks and elements, his size")
check(A.find("vOre") and not A.find("Power") and A.live()[1].x == 854 - 4 - 160, "Aaron's terminal: unchanged")
hs:onGlasses("gl-a", "Aaron", 1200, 600)
hs:draw(MODEL, evaluate, cfg.panels)
check(A.live()[1].x == 1200 - 4 - 160 and B.live()[1].x == 4, "each terminal is placed by its own wearer's GUI size")

local again = huds.new({ ["gl-b"] = B.proxy }, cfg.hud, path)
s = again:settings("Bob")
check(s.own and s.scale == 1.5 and #s.blocks == 2 and s.blocks[2].anchor == "bottom" and s.blocks[1].elements[2].kind == "text",
  "settings come back after a restart")
local f = io.open(path, "w")
f:write('return { Bob = { anchor = "bottom-left", bars = { "Power", 7 }, width = 200, alerts = 2 }, ' ..
  'Cy = { scale = 99, blocks = { { anchor = "middle", x = "a", elements = { { kind = "dial" }, { kind = "text", view = "Ore" } } } } }, [3] = {} }')
f:close()
again = huds.new({}, cfg.hud, path)
s = again:settings("Bob")
check(s.own and s.blocks[1].anchor == "bottom-left" and s.blocks[1].width == 200 and #s.blocks[1].elements == 2
  and s.blocks[1].elements[2].count == 2, "the first editor's form becomes one block")
s = again:settings("Cy")
check(s.scale == 1 and s.blocks[1].anchor == "top-right" and s.blocks[1].x == -4 and #s.blocks[1].elements == 1,
  "bad values in the file are dropped or defaulted")

check(hs:reset("Bob") and not hs:settings("Bob").own, "back to the defaults")
hs:change("Bob", function(x) x.blocks[1].elements = { { kind = "bar", view = "Gone" }, { kind = "bar", view = "Smelt" } } end)
hs:draw(MODEL, evaluate, cfg.panels)
check(B.find("vSmelt") and not B.find("Gone"), "an element whose view was removed is skipped")

local D, E = terminal({}), terminal({})
D.proxy.addRect = function() error("terminal unloaded") end
local hs2 = huds.new({ ["gl-d"] = D.proxy, ["gl-e"] = E.proxy }, cfg.hud, nil)
hs2:draw(MODEL, evaluate, cfg.panels)
check(hs2.error and hs2.error:find("terminal unloaded", 1, true) and E.find("vOre"), "a broken terminal doesn't stop the others")

---------------------------------------------------------------- resolution
local w, h = Gui.resolution(160, 50, 3, 4)
check(w == 73 and h == 50, ("a 3 wide, 4 tall screen: 73 x 50 (got %d x %d)"):format(w, h))
w, h = Gui.resolution(160, 50, 8, 3)
check(w == 160 and h == 28, ("8 x 3: as wide as it goes, 160 x 28 (got %d x %d)"):format(w, h))
check(select(1, Gui.resolution(80, 25, nil, nil)) == 80, "unknown shape: the largest")

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
  local ag = n:endpoint("power-room")
  ag.open(4243)
  local m = metrics.new{ role = "lumen", clock = function() return M.time end }
  local enc = codec.encoder{ node = "power-room", role = "lumen", boot = 3, interval = 5 }
  m:gauge("lumen_fill_ratio", "f"):set(0.95)
  m:gauge("lumen_net_5m_eut", "n", "EU/t"):set(2370)
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
  local ok, e = pcall(H.run, "lens-hub.lua", cfgPath)
  io.stderr = realStderr
  M.onPull = nil
  M.components = {}
  return ok and #written == 0, e or table.concat(written), H.TMP .. "/hub/lens-hud.cfg"
end

local function tapText(text, player, minY, dx)
  local x, y = M.find(text, minY)
  assert(x, "nothing on screen says " .. text)
  return { "touch", "screen", x + (dx or 1), y, 0, player }
end

M.setTime(0)
M.resize(160, 50)
local GA, GB = terminal("Aaron"), terminal({})
local HUB_CFG = [[return {
  panels = { { label = "Power", value = "lumen_fill_ratio", format = "percent" },
             { label = "Net 5m", value = "lumen_net_5m_eut", unit = "EU/t", format = "signed", color = "sign" } },
  hud = { bars = { { label = "Ore", value = "lumen_fill_ratio", max = 1 } } },
}]]
local st = {}
local steps = {
  function() return { "glasses_on", "gl-b", "Bob", 1000, 500 } end,
  function() st.dashHud = M.find(" HUD ", 1) ~= nil; return tapText(" HUD ", "Bob", 1) end,
  function()
    st.editor = M.find("HUD for Bob", 1) and M.find("IN BLOCK 1", 1) and M.find("[✓] Ore", 1) and M.find("[✓] Alerts", 1)
      and M.find("[ ] Power", 1)
    return tapText("[ ] Power", "Aaron", 5)    -- someone else's tap: nothing
  end,
  function() st.locked = M.find("[ ] Power", 5) ~= nil; return tapText("[ ] Power", "Bob", 5) end,
  function() st.added = M.find("[✓] Power", 5) and GB.find("Power") and not GA.find("Power"); return tapText("[ ] Net 5m", "Bob", 5) end,
  function()
    local _, y = M.find("[✓] Net 5m", 5)
    local x = M.find("BAR ", y)
    return { "touch", "screen", x, y, 0, "Bob" }   -- BAR -> TEXT
  end,
  function()
    local v = GB.find("+2.4k EU/t")
    st.text = M.find("TEXT", 5) and v and near(v.color, P.good)
    H.screen("hud-editor")
    return tapText("↖", "Bob", 5)
  end,
  function()
    st.anchored = GB.live()[1].x == 4 and GB.live()[1].y == 4 and GA.live()[1].x == 854 - 164
    return tapText("▶", "Bob", 5, 0)
  end,
  function() st.nudged = GB.live()[1].x == 12 and M.find("top-left, x 12 y 4", 5); return tapText("8px", "Bob", 5, 0) end,
  function()
    st.step = M.find("32px", 5) ~= nil
    local x, y = M.find("▼", 5, 60)                 -- the nudge's, not a list row's
    return { "touch", "screen", x, y, 0, "Bob" }
  end,
  function() st.down = GB.live()[1].y == 36; return tapText(" + ", "Bob", 3, 0) end,          -- a new block
  function()
    st.block2 = M.find("IN BLOCK 2", 5) and M.find("REMOVE 2", 3)
    return tapText("[ ] Net 5m", "Bob", 5)
  end,
  function() st.second = #GB.live() > 8; return tapText("DONE", "Bob", 1) end,
  function() st.closed = M.find("NODES", 1) ~= nil; return tapText(" HUD ", "Aaron", 1) end,
  function() st.aaron = M.find("HUD for Aaron", 1) and M.find("IN BLOCK 1", 1) and not M.find("REMOVE", 1); return nil end,
}
local i = 0
local ok, e, hudPath = runHub({ ["gl-a"] = GA, ["gl-b"] = GB }, HUB_CFG, function(t)
  if t < 3 then return nil end
  i = i + 1
  if steps[i] then return steps[i]() end
  if not st.timeout and t > 90 then st.timeout = M.find("NODES", 1) ~= nil; return { "interrupted" } end
  if t > 120 then return { "interrupted" } end
end)
check(ok, "lens-hub runs with two terminals" .. (ok and "" or (": " .. tostring(e))))
check(st.dashHud, "the dashboard has a HUD button when a terminal is attached")
check(st.editor, "tapping HUD opens the editor for whoever tapped: the block's elements, then what can be added")
check(st.locked, "another player's taps change nothing")
check(st.added, "tapping a view adds it to the tapper's own HUD only")
check(st.text, "BAR / TEXT switches an element to text, colored by its view (green: above zero)")
check(st.anchored, "the anchor grid moves only the tapper's block")
check(st.nudged, "arrows nudge it by the step, and the editor says where it is")
check(st.step and st.down, "the step cycles 1, 8, 32 px")
check(st.block2 and st.second, "+ adds a block, edited on its own")
check(st.closed, "DONE goes back to the dashboard")
check(st.aaron, "another player opens their own editor")
check(st.timeout, "the editor closes after a minute without a tap")
local fh = io.open(hudPath); local saved = fh and fh:read("*a") or ""; if fh then fh:close() end
check(saved:find('["Bob"] = { scale = 1, blocks = {', 1, true)
  and saved:find('{ anchor = "top-left", x = 12, y = 36, width = 160, elements = {', 1, true)
  and saved:find('{ kind = "text", view = "Net 5m" },', 1, true) and not saved:find("Aaron", 1, true),
  "Bob's settings are saved in lens-hud.cfg next to the config; Aaron has none")

-- A 3 x 4 screen: the hub fits it, and the editor and dashboard fit too.
M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
M.oob = 0
local opened
ok = runHub({ ["gl-a"] = terminal("Aaron") }, HUB_CFG, function(t)
  if t < 12 then return nil end                     -- a sparkline sample with data
  if not opened then
    opened = true
    st.portrait = M.find("PANELS", 1) and M.find("NODES", 1) and M.find("▁", 1)
    H.screen("dashboard-portrait")
    return tapText(" HUD ", "Aaron", 1)
  end
  H.screen("hud-editor-portrait")
  st.portraitEditor = M.find("HUD for Aaron", 1) and M.find("↘", 1) and M.find("Size", 1)
  return { "interrupted" }
end)
check(ok and M.resolution[1] == 73 and M.resolution[2] == 50, "resolution fit: 73 x 50 on a 3 x 4 screen")
check(st.portrait and M.oob == 0, "the dashboard uses the height: panels with sparklines, then nodes and alerts")
check(st.portraitEditor and M.oob == 0, "the editor fits")
M.aspect = nil

M.setTime(0)
M.resize(80, 25)
M.oob = 0
opened = nil
ok = runHub({ ["gl-a"] = terminal("Aaron") }, HUB_CFG, function(t)
  if t < 3 then return nil end
  if not opened then opened = true; return tapText(" HUD ", "Aaron", 1) end
  H.screen("hud-editor-tier2")
  return { "interrupted" }
end)
check(ok and M.oob == 0 and M.find("HUD for Aaron", 1) and M.find("↘", 1) and M.find("Width", 1),
  "on a tier 2 screen the editor fits")
M.resize(160, 50)

H.done()
