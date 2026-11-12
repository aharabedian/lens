-- test_board.lua: the view library, the dashboard's panels and players' HUDs kept in lens-board.cfg
-- (lens.hub.board), and the EDIT page and view editor in lens-hub (lens.hub.editors.edit, editors.view): add,
-- order, remove, make and change views with the keyboard, undo, who may edit, one editor at a time. (Typing
-- into a draft on its own: test_hub.) Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local R = require("hubrun")(H)
local board = require("lens.hub.board")
local viewdraft = require("lens.hub.viewdraft")
local config = require("lens.hub.config")
local files = require("lens.files")

local function write(path, text) local f = assert(io.open(path, "w")); f:write(text); f:close() end

---------------------------------------------------------------- lens.hub.board
local cfg = assert(config.check({
  panels = { { label = "Ore", value = "1" }, { label = "Power", value = "2", format = "percent" } },
  hud = { bars = { { label = "Net", value = "3" } } },
}))
local path = H.TMP .. "/lens-board.cfg"
local b = board.new(path, cfg)
local views = b:views()
check(#views == 3 and views[1].label == "Ore" and views[2].format == "percent" and views[3].label == "Net"
  and views[1].source == "config", "the library starts as lens-hub.cfg's panels, then its HUD views")
check(#b:panels() == 2 and b:panels()[2].label == "Power", "the dashboard starts as lens-hub.cfg's panels")
check(b:setPlayers({ Bob = { scale = 1, blocks = { { anchor = "top", elements = { { kind = "bar", view = "Ore" } } } } } })
  and b:players().Bob.blocks[1].anchor == "top", "players' HUDs are kept with the rest")

check(b:setView({ label = "Net 5m", value = "lumen_net_5m_eut", format = "signed", color = "sign" }), "a new view")
check(b:view("Net 5m").source == "screen" and not b:onDashboard("Net 5m"), "it's in the library, not on the dashboard yet")
check(b:setPanels({ "Power", "Net 5m", "Ore" }) and b:panels()[2].label == "Net 5m", "the dashboard's panels, in order")
check(b:setView({ label = "Ore", value = "sum(prism_backlog_items)", max = 10000 }, "Ore") and b:view("Ore").source == "edited"
  and b:view("Ore").max == 10000, "a lens-hub.cfg view changed on the screen overrides it")
local ok, err = b:setView({ label = "Ore!", value = "1" }, "Ore")
check(not ok and err:find("keep their label", 1, true), "lens-hub.cfg's views keep their label")
ok, err = b:setView({ label = "Bad", value = "sum(x" })
check(not ok and err:find("value: expected )", 1, true), "a view is checked like a panel")
ok, err = b:setView({ label = "Power", value = "1" }, "Net 5m")
check(not ok and err:find("already a view called Power", 1, true), "labels stay unique")

b:players().Bob.blocks[1].elements[2] = { kind = "text", view = "Net 5m" }
b:setPlayers(b:players())
check(b:setView({ label = "Net (5 min)", value = "lumen_net_5m_eut" }, "Net 5m") and b:onDashboard("Net (5 min)")
  and b:players().Bob.blocks[1].elements[2].view == "Net (5 min)", "renaming a view: the dashboard and HUDs follow")

local again = board.new(path, cfg)
check(again:panels()[2].label == "Net (5 min)" and again:view("Ore").max == 10000 and again:players().Bob,
  "everything comes back after a restart")
local text = files.read(path)
check(text:find("Written by lens-hub", 1, true) and text:find('label = "Net (5 min)"', 1, true), "lens-board.cfg is readable Lua")

check(b:deleteView("Ore") and b:view("Ore").max == nil and b:view("Ore").source == "config",
  "deleting an edited view: back to lens-hub.cfg's")
ok, err = b:deleteView("Ore")
check(not ok and err:find("take it off the dashboard", 1, true), "a lens-hub.cfg view can't be deleted")
check(b:deleteView("Net (5 min)") and not b:onDashboard("Net (5 min)") and #b:players().Bob.blocks[1].elements == 1,
  "deleting a screen view takes it off the dashboard and out of HUDs")
check(b.canUndo and b:undo() and b:view("Net (5 min)") and b:onDashboard("Net (5 min)"), "undo brings it back")
for _ = 1, 30 do b:undo() end
check(not b.canUndo, "undo goes back as far as it remembers")

-- A panel added to lens-hub.cfg later (lens-setup) shows up once; one taken off on the screen stays off.
b = board.new(path, cfg)
b:setPanels({ "Power" })
local cfg2 = assert(config.check({ panels = { { label = "Ore", value = "1" }, { label = "Power", value = "2" },
  { label = "Smelt", value = "4" } } }))
local b2 = board.new(path, cfg2, nil)
local labels = {}
for _, v in ipairs(b2:panels()) do labels[#labels + 1] = v.label end
check(table.concat(labels, ",") == "Power,Smelt", "a new lens-hub.cfg panel is added once; removed ones stay removed")
check(#board.new(path, cfg2, nil):panels() == 2, "and only once")

---------------------------------------------------------------- pages
do
  local cfgP = assert(config.check({ panels = { { label = "Ore", value = "1" }, { label = "Power", value = "2" } } }))
  local pp = H.TMP .. "/pages.cfg"
  write(pp, 'return { views = {}, panels = { "Power" }, seen = { "Ore", "Power" } }')        -- as 0.2.0 saved it
  local bp = board.new(pp, cfgP)
  local pages = bp:pages()
  check(#pages == 1 and pages[1].name == "Main" and pages[1].count == 1 and bp:panels(1)[1].label == "Power",
    "a 0.2.0 board: its panels become the page Main")
  local i = bp:addPage()
  check(i == 2 and bp:pages()[2].name == "Page 2" and #bp:panels(2) == 0, "+ PAGE: Page 2, empty")
  check(bp:addPanel("Ore", 2) and bp:panels(2)[1].label == "Ore" and #bp:panels(1) == 1, "panels go on one page")
  check(bp:onDashboard("Ore") and bp:onDashboard("Ore", 2) and not bp:onDashboard("Ore", 1), "onDashboard: any page, or one")
  check(#bp:allPanels() == 2, "allPanels: every page's, once")
  check(bp:renamePage(2, "Ore line") and bp:pages()[2].name == "Ore line", "rename")
  check(select(2, bp:renamePage(2, "  ")):find("needs a name", 1, true)
    and select(2, bp:renamePage(2, string.rep("x", 17))):find("at most 16", 1, true), "names: not empty, at most 16")
  local saved = files.loadTable(pp)
  check(saved.pages[2].name == "Ore line" and saved.pages[2].panels[1] == "Ore" and saved.panels == nil,
    "lens-board.cfg: pages with their panels")
  check(bp:deletePage(1) and bp:pages()[1].name == "Ore line", "delete a page (its views stay)")
  check(bp:view("Power") and select(2, bp:deletePage(1)) == "the last page stays", "the last page stays")
  check(bp:undo() and #bp:pages() == 2 and bp:pages()[1].name == "Main", "undo brings a page back")
  for _ = 1, 10 do bp:addPage() end
  check(#bp:pages() == 8, "at most 8 pages")
  local cfg3 = assert(config.check({ panels = { { label = "Ore", value = "1" }, { label = "Power", value = "2" },
    { label = "Smelt", value = "3" } } }))
  local b3 = board.new(pp, cfg3)
  check(b3:panels(1)[#b3:panels(1)].label == "Smelt", "a new lens-hub.cfg panel goes on the first page")
end

---------------------------------------------------------------- in lens-hub
local POWER = R.agent{ node = "power-room", role = "lumen", setup = function(m)
  m:gauge("lumen_fill_ratio", "f"):set(0.95)
  m:gauge("lumen_net_5m_eut", "n", "EU/t"):set(-2370)
end }

local function runHub(cfgText, script, opts)
  opts = opts or {}
  return R.run{ cfg = cfgText, dir = opts.dir, agents = { POWER }, keyboard = opts.keyboard ~= false,
    script = function(t)
      local e = script(t)
      if e == nil and t > 200 then return "stop" end
      return e
    end }
end
local tap = R.tap

local HUB_CFG = [[return { panels = { { label = "Power", value = "lumen_fill_ratio", format = "percent" } } }]]

M.setTime(0)
M.resize(160, 50)
local st = {}
local steps = {
  function() st.button = M.find(" EDIT ", 1) ~= nil; return tap(" EDIT ", "Aaron", 1) end,
  function()
    st.page = M.find("Edit the dashboard", 1) and M.find("ON MAIN (1)", 1) and M.find("95%", 3)
    return tap(" EDIT ", "Bob", 1)           -- Bob can't open one while Aaron's is open; he sees the EDIT page
  end,
  function() st.bobBlocked = M.find("Edit the dashboard", 1) ~= nil; return tap("+ NEW", "Aaron", 3) end,
  function()
    st.newView = M.find("New view", 1) and M.find("Label", 3)
    R.queue(R.keys("Net 5m", "Bob"))         -- Bob's typing is ignored
    R.queue(R.keys("Net 5m", "Aaron"))
    R.queue(R.key(viewdraft.KEYS.enter, "Aaron"), R.paste("lumen_net_5m_eut", "Aaron"))
    return nil
  end,
  function()
    local _, fy = M.find("Format", 3)
    local qx, qy = M.find("lumen_net_5m_eut", 3)
    st.typed = M.find("Net 5m", 3) and not M.find("Net 5mNet 5m", 3) and qx and M.bgAt(qx + 16, qy) == 0xe6e9ec  -- the cursor cell
      and M.find("-2.4k", fy)
    st.typedOnce = true
    return { "touch", "screen", 16, fy, 0, "Aaron" }   -- format: auto -> percent
  end,
  function()
    local _, fy = M.find("Format", 3)
    R.queue({ "touch", "screen", 16, fy, 0, "Aaron" }, { "touch", "screen", 16, fy, 0, "Aaron" })  -- duration, signed
    local _, cy = M.find("Color", 3)
    R.queue({ "touch", "screen", 16, cy, 0, "Aaron" })                         -- thresholds -> sign
    return nil
  end,
  function()
    H.screen("view-editor")
    local pv = M.find("-2.4k", 3)
    local _, py = M.find("Now", 3)
    st.preview = pv and M.fgAt(pv, py) == 0xff5c5c
    return tap("SAVE", "Aaron", 1)
  end,
  function()
    st.saved = M.find("ON MAIN (2)", 1) and M.find("Net 5m", 4)
    H.screen("dash-editor")
    local _, y = M.find("Net 5m", 4)
    return { "touch", "screen", M.find("▲", y), y, 0, "Aaron" }
  end,
  function()
    local _, py = M.find("Power", 4)
    local _, ny = M.find("Net 5m", 4)
    st.moved = ny < py
    return tap("UNDO", "Aaron", 1)
  end,
  function()
    local _, py = M.find("Power", 4)
    local _, ny = M.find("Net 5m", 4)
    st.undone = py < ny
    local _, y = M.find("Power", 4)
    return { "touch", "screen", M.find("✕", y), y, 0, "Aaron" }
  end,
  function()
    st.removed = M.find("ON MAIN (1)", 1) and M.find("LIBRARY (1)", 1)
    return tap("DONE", "Aaron", 1)
  end,
  function()
    local _, y = M.find("Net 5m", 3)
    local vx = M.find("-2.4k", y)
    st.dash = M.find("PANELS", 1) and vx and M.fgAt(vx, y) == 0xff5c5c and not M.find("95%", 3)
    return tap(" EDIT ", "Bob", 1)
  end,
  function() st.bobNow = M.find("Edit the dashboard", 1) ~= nil; return tap("DONE", "Bob", 1) end,
}
local i = 0
local e, dir
ok, e, dir = runHub(HUB_CFG, function(t)
  if t < 3 then return nil end
  i = i + 1
  if steps[i] then return steps[i]() end
  return "stop"
end)
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(e))))
check(st.button and st.page, "EDIT opens the dashboard's EDIT page: its panels with their values")
check(st.bobBlocked, "while it's open, someone else can't take it over")
check(st.newView, "+ NEW opens a new view")
check(st.typed, "typing fills the field (only from the player editing), Enter goes on, a paste lands; the value is previewed")
check(st.preview, "format and color cycle by tapping; the preview follows (signed, red below zero)")
check(st.saved, "SAVE puts a new view on the dashboard")
check(st.moved and st.undone, "▲ orders panels; UNDO takes the last change back")
check(st.removed, "✕ takes a panel off the dashboard; it stays in the library")
check(st.dash, "the dashboard shows the new view, formatted and colored")
check(st.bobNow, "after DONE, someone else can edit")
local saved = files.loadTable(dir .. "/lens-board.cfg")
check(saved and saved.views[1].label == "Net 5m" and saved.views[1].format == "signed" and saved.pages[1].panels[1] == "Net 5m"
  and #saved.pages[1].panels == 1, "lens-board.cfg has the view and the dashboard")
check(files.read(dir .. "/lens-hub.cfg") == HUB_CFG, "lens-hub.cfg is untouched")

-- editors: only those players may open EDIT.
M.setTime(0)
st = {}
i = 0
ok = runHub([[return { editors = { "Aaron" }, panels = {} }]], function(t)
  if t < 3 then return nil end
  i = i + 1
  if i == 1 then return tap(" EDIT ", "Bob", 1) end
  if i == 2 then st.refused = M.find("Only Aaron can edit the dashboard.", 1) and M.find("PANELS", 1); return tap(" EDIT ", "Aaron", 1) end
  if i == 3 then st.allowed = M.find("Edit the dashboard", 1) ~= nil end
  return "stop"
end, { dir = "editors" })
check(ok and st.refused and st.allowed, "editors: only they may edit; anyone else is told who can")

-- No keyboard: the view editor says so; a 3 x 4 screen fits both pages.
M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
M.oob = 0
st = {}
i = 0
ok = runHub(HUB_CFG, function(t)
  if t < 3 then return nil end
  i = i + 1
  if i == 1 then return tap(" EDIT ", "Aaron", 1) end
  if i == 2 then st.stacked = M.find("ON MAIN", 1) and M.find("LIBRARY", 4); H.screen("dash-editor-portrait")
    return tap("EDIT", "Aaron", 4) end
  if i == 3 then st.noKb = M.find("No keyboard on this screen", 1) and M.find("View: Power", 1); H.screen("view-editor-portrait") end
  return "stop"
end, { keyboard = false, dir = "portrait" })
check(ok and st.stacked and st.noKb and M.oob == 0, "no keyboard: the editor says so; both pages fit a 3 x 4 screen")
M.aspect = nil
M.resize(160, 50)

H.done()
