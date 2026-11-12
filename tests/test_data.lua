-- test_data.lua: the DATA page in lens-hub (lens.hub.editors.data, pages.data): every metric, its series,
-- queries built by tapping, and turning one into a panel or a HUD element through the view editor; editors,
-- paging, a narrow screen. (explore and store:metrics on their own: test_hub.) Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local R = require("hubrun")(H)
local files = require("lens.files")
local glassesMock = require("glasses")

---------------------------------------------------------------- in lens-hub
-- A LUMEN with two LSCs, and a PRISM with a counter (and, for paging, `extra` more gauges).
local function agents(extra)
  local lumen = R.agent{ node = "power-room", role = "lumen", setup = function(m)
    local net5 = m:gauge("lumen_net_5m_eut", "EU/t in minus out, averaged over 5 min", "EU/t")
    net5:set(2370, { lsc = "Main" })
    net5:set(-500, { lsc = "Spare" })
    m:gauge("lumen_fill_ratio", "How full", "0..1"):set(0.95, { lsc = "Main" })
  end }
  local routed
  local prism = R.agent{ node = "prism-ore", role = "prism", setup = function(m)
    routed = m:counter("prism_items_routed_total", "Items moved to outputs", "items")
    for n = 1, extra or 0 do m:gauge(("prism_extra_%02d"):format(n), "extra"):set(n) end
  end, cycle = function() routed:add(50) end }
  return { lumen, prism }
end

local function runHub(cfgText, script, opts)
  opts = opts or {}
  return R.run{ cfg = cfgText, dir = opts.dir, agents = agents(opts.extra), keyboard = true,
    terminals = opts.glasses and { ["gl-a"] = opts.glasses } or nil, script = function(t)
      local e = script(t)
      if e == nil and t > 200 then return "stop" end
      return e
    end }
end
local tap = R.tap

M.setTime(0)
M.resize(160, 50)
local G = glassesMock.new()
local st = {}
local steps = {
  function() st.button = M.find(" DATA ", 1) ~= nil; return tap(" DATA ", "Aaron", 1) end,
  function()
    st.list = M.find("METRICS (3)", 1) and M.find("lumen_net_5m_eut", 3) and M.find("prism_items_routed_total", 3)
      and M.find("ctr", 3)
    return tap("lumen_net_5m_eut", "Aaron", 3)
  end,
  function()
    st.detail = M.find("lumen_net_5m_eut  (EU/t)", 3) and M.find("EU/t in minus out", 3) and M.find("SERIES (2)", 3)
      and M.find("node=power-room lsc=Main", 3) and M.find("query", 3) and M.find("sum(lumen_net_5m_eut)", 3)
      and M.find("1.9k EU/t", 3)
    return tap(" Main ", "Bob", 3)                 -- not Bob's page
  end,
  function() st.locked = M.find("SERIES (2)", 3) ~= nil; return tap(" Main ", "Aaron", 3) end,
  function()
    st.filtered = M.find('sum(lumen_net_5m_eut{lsc="Main"})', 3) and M.find("SERIES (1)", 3) and M.find("2.4k EU/t", 3)
    H.screen("data")
    local _, cy = M.find("combine", 3)
    return tap(" min ", "Aaron", cy)
  end,
  function()
    st.fn = M.find('min(lumen_net_5m_eut{lsc="Main"})', 3) ~= nil
    local _, cy = M.find("combine", 3)
    return tap(" sum ", "Aaron", cy)
  end,
  function() return tap("SAVE AS PANEL", "Aaron", 3) end,
  function()
    st.editor = M.find("New view", 1) and M.find("net 5m eut · Main", 3) and M.find('sum(lumen_net_5m_eut{lsc="Main"})', 3)
      and M.find("EU/t", 3)
    return tap("SAVE", "Aaron", 1)
  end,
  function()
    st.backToData = M.find('sum(lumen_net_5m_eut{lsc="Main"})', 3) and M.find("SERIES (1)", 3)
    return tap("ADD TO MY HUD", "Aaron", 3)
  end,
  function()
    -- A label of its own, so it's a second view.
    local _, y = M.find("Label", 3)
    return { "touch", "screen", 20, y, 0, "Aaron" }
  end,
  function() return R.paste(" (HUD)", "Aaron") end,
  function() return tap("SAVE", "Aaron", 1) end,
  function()
    st.hud = G.find("net 5m eut") ~= nil
    return tap("prism_items_routed_total", "Aaron", 3)
  end,
  function()
    st.counter = M.find("rate(prism_items_routed_total)", 3) and M.find("items/s", 3) and M.find("/s", 3)
    return tap("DONE", "Aaron", 1)
  end,
  function()
    local _, y = M.find("net 5m eut · Main", 3)
    st.panel = M.find("PANELS", 1) and y and M.find("2.4k EU/t", y)
  end,
}
local i = 0
local ok, err, dir = runHub("return { panels = {} }", function(t)
  if t < 6 then return nil end
  i = i + 1
  if steps[i] then return steps[i]() end
  return "stop"
end, { glasses = G })
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(st.button and st.list, "DATA lists every metric from every agent, with counters marked")
check(st.detail, "a metric: its unit, help, every series with labels and values, and the query so far with its value")
check(st.locked, "only the player who opened it can change it")
check(st.filtered, "tapping a label value filters: the query and series follow")
check(st.fn, "tapping a function changes how the series combine")
check(st.editor, "SAVE AS PANEL opens a new view with the query, a label and the unit")
check(st.backToData, "saving goes back to the DATA page as it was")
check(st.hud, "ADD TO MY HUD saves a view and puts it in the player's HUD")
check(st.counter, "a counter starts as a rate, per second")
check(st.panel, "the new panel is on the dashboard")
local board = files.loadTable(dir .. "/lens-board.cfg")
local hudEls = board and board.huds and board.huds.Aaron and board.huds.Aaron.blocks[1].elements
check(board and #board.views == 2 and board.panels[1] == "net 5m eut · Main" and #board.panels == 1
  and hudEls and hudEls[#hudEls].kind == "text" and hudEls[#hudEls].view == "net 5m eut · Main (HUD)",
  "lens-board.cfg: both views; one on the dashboard, the other in Aaron's HUD")

-- editors: no SAVE AS PANEL for others; a narrow screen shows the list, then a metric with a way back; paging.
M.setTime(0)
M.resize(73, 50)
M.oob = 0
st, i = {}, 0
ok = runHub('return { editors = { "Aaron" } }', function(t)
  if t < 6 then return nil end
  i = i + 1
  if i == 1 then return tap(" DATA ", "Bob", 1) end
  if i == 2 then
    st.paged = M.find("page 1 of 2", 3) and M.find("▶", 3)
    return tap("▶", "Bob", 3)
  end
  if i == 3 then st.page2 = M.find("page 2 of 2", 3) and M.find("prism_items_routed_total", 3); return tap("prism_items_routed_total", "Bob", 3) end
  if i == 4 then
    st.narrow = M.find("◀ METRICS", 3) and not M.find("METRICS (", 3) and not M.find("SAVE AS PANEL", 3)
      and M.find("Only Aaron can add panels.", 3)
    H.screen("data-portrait")
    return tap("◀ METRICS", "Bob", 3)
  end
  if i == 5 then st.backList = M.find("METRICS (", 3) ~= nil end
  return "stop"
end, { extra = 50, dir = "narrow" })
check(ok and st.paged and st.page2, "many metrics: pages")
check(st.narrow and st.backList, "a narrow screen: the list, then one metric with a way back")
check(M.oob == 0, "it fits a 3 x 4 screen")
M.resize(160, 50)

H.done()
