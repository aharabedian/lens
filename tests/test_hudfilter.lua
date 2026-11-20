-- test_hudfilter.lua: an alerts element that shows only some nodes' alerts (nodes, a Lua pattern) or only BAD ones
-- (level = "bad"). Checked in lens-hub.cfg; through lens-hub: set in lens-hub.cfg, and in the HUD editor with NODES
-- (all, prism-*, each node) and BAD ONLY, kept in lens-board.cfg; the glasses show only those. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local config = require("lens.hub.config")
local hudEditor = require("lens.hub.editors.hud")
local files = require("lens.files")
local glassesMock = require("glasses")

local function hudCfg(el)
  return { hud = { blocks = { { elements = { el } } } } }
end
check(config.check(hudCfg({ kind = "alerts", nodes = "^prism", level = "bad" })), "alerts: nodes and level")
check(select(2, config.check(hudCfg({ kind = "alerts", nodes = "[" }))):find("Lua pattern", 1, true),
  "a pattern that doesn't work is refused")
check(select(2, config.check(hudCfg({ kind = "alerts", level = "warn" }))):find('level must be "bad"', 1, true),
  "level is bad or nothing")
check(hudEditor.nodesText(nil) == "all" and hudEditor.nodesText("^prism%-") == "prism-*"
  and hudEditor.nodesText("^power%-room$") == "power-room" and hudEditor.nodesText("ore") == "ore",
  "the editor's names for node filters")

local function agents()
  return {
    R.agent{ node = "prism-ore", role = "prism", cycle = function(m)
      m:beginCycle()
      m:alert("power:mac2", "bad", "Macerator 2: no power")
      m:alert("idle:wash1", "warn", "Washer 1 idle")
    end },
    R.agent{ node = "prism-nether-ore", role = "prism", cycle = function(m)
      m:beginCycle()
      m:alert("power:mac1", "bad", "Nether macerator: no power")
    end },
    R.agent{ node = "power-room", role = "lumen", cycle = function(m)
      m:beginCycle()
      m:alert("reactor:N-3", "bad", "Reactor N-3: fault signal")
    end },
  }
end

local G = glassesMock.new()
local function hudSays(text)
  for _, s in ipairs(G.live()) do if s.visible ~= false and (s.text or ""):find(text, 1, true) then return true end end
  return false
end

-- In lens-hub.cfg.
M.setTime(0)
local seen = {}
local ok, err = R.run{ cfg = 'return { hud = { blocks = { { elements = { { kind = "alerts", count = 5, nodes = "^power" } } } } } }',
  dir = "cfg", agents = agents(), terminals = { gl000000 = G }, script = function(t)
  if t < 12 then return nil end
  seen.cfg = hudSays("Reactor N-3") and not hudSays("Macerator") and not hudSays("Nether")
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.cfg, "nodes in lens-hub.cfg: only those nodes' alerts in the HUD")

-- In the HUD editor.
G = glassesMock.new()
seen = {}
local step = 0
local dir
ok, err, dir = R.run{ cfg = "return {}", agents = agents(), terminals = { gl000000 = G }, script = function(t)
  if t < 12 then return nil end
  step = step + 1
  if step == 1 then seen.on = t; return { "glasses_on", "gl000000", "Aaron", 854, 480 } end
  if t < seen.on + 2 then step = step - 1; return nil end      -- the next tick draws the HUD
  if step == 2 then
    seen.all = hudSays("Reactor N-3") and hudSays("Macerator 2") and hudSays("Nether macerator") and hudSays("+1 more")
    return R.tap(" HUD ", "Aaron", 1)
  end
  if step == 3 then seen.offered = M.find("NODES: all", 3) and M.find("BAD ONLY", 3); return R.tap("NODES: all", "Aaron", 3) end
  if step == 4 then seen.prefix = M.find("NODES: prism-*", 3) ~= nil; return R.tap("BAD ONLY", "Aaron", 3) end
  if step == 5 then
    H.screen("hud-filter-editor")
    seen.filtered = hudSays("Macerator 2") and hudSays("Nether macerator") and not hudSays("Washer")
      and not hudSays("Reactor")
    return R.tap("NODES: prism-*", "Aaron", 3)
  end
  if step == 6 then
    seen.next = M.find("NODES: power-room", 3) or M.find("NODES: prism-nether-ore", 3) or M.find("NODES: prism-ore", 3)
    return R.tap("DONE", "Aaron", 1)
  end
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.all, "no filter: every node's alerts")
check(seen.offered and seen.prefix, "the HUD editor offers NODES and BAD ONLY; NODES goes to a prefix two nodes share")
check(seen.filtered, "prism-* and BAD ONLY: only the prism nodes' BAD alerts")
check(seen.next, "then each node by name")
local saved = files.loadTable(dir .. "/lens-board.cfg")
local el = saved and saved.huds and saved.huds.Aaron and saved.huds.Aaron.presets
  and saved.huds.Aaron.presets[1].blocks[1].elements[1]
check(el and el.kind == "alerts" and el.level == "bad" and type(el.nodes) == "string", "kept in lens-board.cfg")

H.done()
