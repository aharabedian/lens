-- test_huds.lua: a HUD per Glasses Terminal, each showing its wearer's settings (lens.hub.huds, kept by a
-- store), and the HUD editor in lens-hub (lens.hub.editors.hud, pages.hud): blocks, elements, anchors, nudges,
-- only the tapping player, saved in lens-board.cfg, closing by itself, on 160 x 50, 73 x 50 and 80 x 25.
-- (Drawing blocks on one terminal: test_hud.) Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local hud = require("lens.hub.hud")
local huds = require("lens.hub.huds")
local config = require("lens.hub.config")
local files = require("lens.files")
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
-- A store like lens.hub.board's players / setPlayers.
local function store(players)
  local s = { saved = 0, data = players or {} }
  function s.players() return s.data end
  function s.setPlayers(_, p) s.data, s.saved = p, s.saved + 1; return true end
  return s
end

---------------------------------------------------------------- lens.hub.huds
local MODEL = { now = 1, health = "ok", alerts = {}, nodes = {}, panels = {} }
local cfg = assert(config.check({
  panels = { { label = "Power", value = "1" }, { label = "Ore", value = "2" }, { label = "Smelt", value = "3" } },
  hud = { bars = { { label = "Ore", value = "sum(x)", max = 10 } } },
}))
local function evaluate(views)
  local out = {}
  for i, v in ipairs(views) do out[i] = { label = v.label, text = "v" .. v.label, frac = 0.5 } end
  return out
end
local A, B, C = terminal("Aaron"), terminal({}), terminal({ "Aaron", "Bob" })
local st = store()
local hs = huds.new({ ["gl-a"] = A.proxy, ["gl-b"] = B.proxy, ["gl-c"] = C.proxy }, cfg.hud, st)

local cat = hs:catalog(cfg.panels)
check(#cat == 3 and cat[1].label == "Power" and cat[2].label == "Ore" and cat[2].max == nil and cat[3].label == "Smelt",
  "the catalog: the library's views (here the panels) first, then the default HUD's with other labels")
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
end) and st.saved == 1, "a change goes to the store")
hs:onGlasses("gl-b", "Bob", 1000, 500)
hs:draw(MODEL, evaluate, cfg.panels)
local pw, sm = B.find("Power"), B.find("vSmelt")
check(pw and sm and pw.y < sm.y and not B.find("vOre") and pw.scale == 1.5 and B.live()[1].x == 4,
  "Bob's terminal: his blocks and elements, his size")
check(A.find("vOre") and not A.find("Power") and A.live()[1].x == 854 - 4 - 160, "Aaron's terminal: unchanged")
hs:onGlasses("gl-a", "Aaron", 1200, 600)
hs:draw(MODEL, evaluate, cfg.panels)
check(A.live()[1].x == 1200 - 4 - 160 and B.live()[1].x == 4, "each terminal is placed by its own wearer's GUI size")

s = huds.new({ ["gl-b"] = B.proxy }, cfg.hud, st):settings("Bob")
check(s.own and s.scale == 1.5 and #s.blocks == 2 and s.blocks[2].anchor == "bottom" and s.blocks[1].elements[2].kind == "text",
  "settings come back from the store")
local odd = huds.new({}, cfg.hud, store({
  Bob = { anchor = "bottom-left", bars = { "Power", 7 }, width = 200, alerts = 2 },
  Cy = { scale = 99, blocks = { { anchor = "middle", x = "a", elements = { { kind = "dial" }, { kind = "text", view = "Ore" } } } } },
  [3] = {},
}))
s = odd:settings("Bob")
check(s.own and s.blocks[1].anchor == "bottom-left" and s.blocks[1].width == 200 and #s.blocks[1].elements == 2
  and s.blocks[1].elements[2].count == 2, "the first editor's form (bars, anchor) becomes one block")
s = odd:settings("Cy")
check(s.scale == 1 and s.blocks[1].anchor == "top-right" and s.blocks[1].x == -4 and #s.blocks[1].elements == 1,
  "bad values are dropped or defaulted")

check(hs:reset("Bob") and not hs:settings("Bob").own, "back to the defaults")
hs:change("Bob", function(x) x.blocks[1].elements = { { kind = "bar", view = "Gone" }, { kind = "bar", view = "Smelt" } } end)
hs:draw(MODEL, evaluate, cfg.panels)
check(B.find("vSmelt") and not B.find("Gone"), "an element whose view was removed is skipped")

local D, E = terminal({}), terminal({})
D.proxy.addRect = function() error("terminal unloaded") end
local hs2 = huds.new({ ["gl-d"] = D.proxy, ["gl-e"] = E.proxy }, cfg.hud)
hs2:draw(MODEL, evaluate, cfg.panels)
check(hs2.error and hs2.error:find("terminal unloaded", 1, true) and E.find("vOre"), "a broken terminal doesn't stop the others")

---------------------------------------------------------------- the editor, in lens-hub
local POWER = R.agent{ node = "power-room", role = "lumen", setup = function(m)
  m:gauge("lumen_fill_ratio", "f"):set(0.95)
  m:gauge("lumen_net_5m_eut", "n", "EU/t"):set(2370)
end }
local HUB_CFG = [[return {
  panels = { { label = "Power", value = "lumen_fill_ratio", format = "percent" },
             { label = "Net 5m", value = "lumen_net_5m_eut", unit = "EU/t", format = "signed", color = "sign" } },
  hud = { bars = { { label = "Ore", value = "lumen_fill_ratio", max = 1 } } },
}]]

M.setTime(0)
M.resize(160, 50)
local GA, GB = terminal("Aaron"), terminal({})
local seen = {}
local steps = {
  function() return { "glasses_on", "gl-b", "Bob", 1000, 500 } end,
  function() seen.dashHud = M.find(" HUD ", 1) ~= nil; return R.tap(" HUD ", "Bob", 1) end,
  function()
    seen.editor = M.find("HUD for Bob", 1) and M.find("IN BLOCK 1", 1) and M.find("[✓] Ore", 1)
      and M.find("[✓] Alerts", 1) and M.find("[ ] Power", 1)
    return R.tap("[ ] Power", "Aaron", 5)    -- someone else's tap: nothing
  end,
  function() seen.locked = M.find("[ ] Power", 5) ~= nil; return R.tap("[ ] Power", "Bob", 5) end,
  function()
    seen.added = M.find("[✓] Power", 5) and GB.find("Power") and not GA.find("Power")
    return R.tap("[ ] Net 5m", "Bob", 5)
  end,
  function()
    local _, y = M.find("[✓] Net 5m", 5)
    return { "touch", "screen", M.find("BAR ", y), y, 0, "Bob" }   -- BAR -> TEXT
  end,
  function()
    local v = GB.find("+2.4k EU/t")
    seen.text = M.find("TEXT", 5) and v and near(v.color, P.good)
    H.screen("hud-editor")
    return R.tap("↖", "Bob", 5)
  end,
  function()
    seen.anchored = GB.live()[1].x == 4 and GB.live()[1].y == 4 and GA.live()[1].x == 854 - 164
    return R.tap("▶", "Bob", 5)
  end,
  function()
    seen.nudged = GB.live()[1].x == 12 and M.find("top-left, x 12 y 4", 5)
    return R.tap("8px", "Bob", 5)
  end,
  function()
    seen.step = M.find("32px", 5) ~= nil
    return R.tap("▼", "Bob", 5, 60)                  -- the nudge's, not a list row's
  end,
  function() seen.down = GB.live()[1].y == 36; return R.tap(" + ", "Bob", 3) end,   -- a new block
  function()
    seen.block2 = M.find("IN BLOCK 2", 5) and M.find("REMOVE 2", 3)
    return R.tap("[ ] Net 5m", "Bob", 5)
  end,
  function() seen.second = #GB.live() > 8; return R.tap("DONE", "Bob", 1) end,
  function() seen.closed = M.find("NODES", 1) ~= nil; return R.tap(" HUD ", "Aaron", 1) end,
  function() seen.aaron = M.find("HUD for Aaron", 1) and M.find("IN BLOCK 1", 1) and not M.find("REMOVE", 1) end,
}
local i = 0
local ok, err, dir = R.run{ cfg = HUB_CFG, agents = { POWER }, terminals = { ["gl-a"] = GA, ["gl-b"] = GB },
  script = function(t)
    if t < 3 then return nil end
    i = i + 1
    if steps[i] then return steps[i]() end
    if t > 90 then seen.timeout = M.find("NODES", 1) ~= nil; return "stop" end
  end }
check(ok, "lens-hub runs with two terminals" .. (ok and "" or (": " .. tostring(err))))
check(seen.dashHud, "the dashboard has a HUD button when a terminal is attached")
check(seen.editor, "tapping HUD opens the editor for whoever tapped: the block's elements, then what can be added")
check(seen.locked, "another player's taps change nothing")
check(seen.added, "tapping a view adds it to the tapper's own HUD only")
check(seen.text, "BAR / TEXT switches an element to text, colored by its view (green: above zero)")
check(seen.anchored, "the anchor grid moves only the tapper's block")
check(seen.nudged, "arrows nudge it by the step, and the editor says where it is")
check(seen.step and seen.down, "the step cycles 1, 8, 32 px")
check(seen.block2 and seen.second, "+ adds a block, edited on its own")
check(seen.closed, "DONE goes back to the dashboard")
check(seen.aaron, "another player opens their own editor")
check(seen.timeout, "the editor closes after a minute without a tap")
local saved = files.loadTable(dir .. "/lens-board.cfg") or {}
local bob = saved.huds and saved.huds.Bob
local blk = bob and bob.blocks[1]
check(bob and bob.scale == 1 and blk.anchor == "top-left" and blk.x == 12 and blk.y == 36 and blk.width == 160
  and blk.elements[#blk.elements].kind == "text" and blk.elements[#blk.elements].view == "Net 5m" and not saved.huds.Aaron,
  "Bob's settings are saved in lens-board.cfg next to the config; Aaron has none")

-- A long list of views: the block's list is cut with "+N more", and the position controls still show.
M.setTime(0)
M.resize(80, 25)
M.oob = 0
local many = { "return { panels = {" }
for n = 1, 30 do many[#many + 1] = ('{ label = "View %02d", value = "1" },'):format(n) end
many[#many + 1] = "} }"
local opened
ok = R.run{ cfg = table.concat(many, "\n"), dir = "many", terminals = { ["gl-a"] = terminal("Aaron") },
  script = function(t)
    if t < 3 then return nil end
    if not opened then opened = true; return R.tap(" HUD ", "Aaron", 1) end
    H.screen("hud-editor-tier2")
    seen.long = M.find("more", 5) and M.find("POSITION", 1) and M.find("↘", 1) and M.find("Width", 1)
      and M.find("Only Aaron can change this", 1)
    return "stop"
  end }
check(ok and seen.long and M.oob == 0, "on a tier 2 screen with a long list: cut with +N more, the rest still drawn")

-- A 3 x 4 screen: the editor fits.
M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
M.oob = 0
opened = nil
ok = R.run{ cfg = HUB_CFG, agents = { POWER }, terminals = { ["gl-a"] = terminal("Aaron") }, script = function(t)
  if t < 3 then return nil end
  if not opened then opened = true; return R.tap(" HUD ", "Aaron", 1) end
  H.screen("hud-editor-portrait")
  seen.portrait = M.find("HUD for Aaron", 1) and M.find("↘", 1) and M.find("Size", 1)
  return "stop"
end }
check(ok and seen.portrait and M.oob == 0, "the editor fits a 3 x 4 screen (73 x 50)")
M.aspect = nil
M.resize(160, 50)

H.done()
