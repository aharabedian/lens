-- test_data.lua: the DATA page: every metric (store:metrics), queries built by tapping (lens.hub.explore),
-- and turning one into a panel or a HUD element through the view editor. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local explore = require("lens.hub.explore")
local store = require("lens.hub.store")
local query = require("lens.hub.query")
local files = require("lens.files")
local glassesMock = require("glasses")

---------------------------------------------------------------- explore
check(explore.query("lumen_net_5m_eut", {}, "sum") == "sum(lumen_net_5m_eut)", "no filters: the metric")
local q = explore.query("m", { lsc = 'Say "hi"\\', node = "power-room" }, "max")
check(q == 'max(m{node="power-room", lsc="Say \\"hi\\"\\\\"})', "filters sorted (node first), quotes and backslashes escaped")
local compiled = query.compile(q)
check(compiled and compiled(function()
  return { { value = 7, labels = { node = "power-room", lsc = 'Say "hi"\\' } }, { value = 9, labels = { node = "x", lsc = "y" } } }
end) == 7, "and the query reads back as the same value")
local series = {
  { labels = { node = "power-room", lsc = "Main" } }, { labels = { node = "power-room", lsc = "Spare" } },
  { labels = { node = "power-base", lsc = "Main" } },
}
local labels = explore.labels(series, { node = "power-base" })
check(labels[1].label == "node" and #labels[1].values == 2 and labels[1].chosen == "power-base"
  and labels[2].label == "lsc" and #labels[2].values == 1 and labels[2].values[1] == "Main",
  "labels: node first; choosing one narrows the others' values")
check(explore.labelText({ lsc = "Main", node = "power-room" }) == "node=power-room lsc=Main", "label text, node first")
check(explore.suggestLabel("lumen_net_5m_eut", { lsc = "Main", node = "x" }) == "net 5m eut · Main", "a starting label")

---------------------------------------------------------------- store:metrics
local s = store.new{ staleAfter = 3 }
s:receive({ kind = "describe", node = "a", boot = 1, metrics = { x_total = { type = "counter", help = "X done", unit = "items" } } }, 0)
s:receive({ kind = "snapshot", node = "a", boot = 1, interval = 5, samples = { { "x_total", 3 }, { "y", 1, { k = "1" } }, { "y", 2, { k = "2" } } } }, 0)
s:receive({ kind = "snapshot", node = "b", boot = 1, interval = 5, samples = { { "y", 5 } } }, 0)
local ms = s:metrics(1)
check(#ms == 2 and ms[1].name == "x_total" and ms[1].type == "counter" and ms[1].help == "X done" and ms[1].unit == "items"
  and ms[2].name == "y" and ms[2].series == 3 and #ms[2].nodes == 2 and ms[2].type == "gauge",
  "store:metrics: every metric, its type, help, unit, series and nodes")
check(#s:metrics(100) == 0, "stale nodes' metrics are left out")

---------------------------------------------------------------- in lens-hub
local net = require("net")
local codec = require("lens.codec")
local metrics = require("lens.metrics")

local function runHub(cfgText, script, opts)
  opts = opts or {}
  M.components = { ["kb000000"] = { type = "keyboard", methods = {} } }
  if opts.glasses then M.components["gl-a"] = { type = "glasses", proxy = opts.glasses.proxy, methods = {} } end
  local dir = H.TMP .. "/" .. (opts.dir or "hub")
  os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
  local f = assert(io.open(dir .. "/lens-hub.cfg", "w")); f:write(cfgText); f:close()
  local n = net.new()
  M.modem = n:endpoint("hub")
  local agents = {}
  for _, a in ipairs({ { "power-room", "lumen" }, { "prism-ore", "prism" } }) do
    local ep = n:endpoint(a[1])
    ep.open(4243)
    local m = metrics.new{ role = a[2], clock = function() return M.time end }
    agents[#agents + 1] = { ep = ep, m = m, enc = codec.encoder{ node = a[1], role = a[2], boot = 3, interval = 5 } }
  end
  local lumen, prism = agents[1].m, agents[2].m
  local net5 = lumen:gauge("lumen_net_5m_eut", "EU/t in minus out, averaged over 5 min", "EU/t")
  net5:set(2370, { lsc = "Main" })
  net5:set(-500, { lsc = "Spare" })
  lumen:gauge("lumen_fill_ratio", "How full", "0..1"):set(0.95, { lsc = "Main" })
  local routed = prism:counter("prism_items_routed_total", "Items moved to outputs", "items")
  for i = 1, (opts.extra or 0) do prism:gauge("prism_extra_" .. string.format("%02d", i), "extra"):set(i) end
  local nextPush = 0
  M.onPull = function()
    if M.time >= nextPush then
      routed:add(50)
      for _, a in ipairs(agents) do
        for _, p in ipairs(a.enc:describe(a.m:describe())) do a.ep.broadcast(4243, p) end
        for _, p in ipairs(a.enc:snapshot(a.m:snapshot())) do a.ep.broadcast(4243, p) end
      end
      nextPush = M.time + 5
    end
    local ev = n.pop(M.modem)
    if ev then return ev end
    return script(M.time)
  end
  local realStderr, written = io.stderr, {}
  io.stderr = { write = function(_, x) written[#written + 1] = x end }
  local fine, e = pcall(H.run, "lens-hub.lua", dir .. "/lens-hub.cfg")
  io.stderr = realStderr
  M.onPull = nil
  M.components = {}
  return fine and #written == 0, e or table.concat(written), dir
end

local function tap(what, player, minY, minX)
  local x, y = M.find(what, minY, minX)
  assert(x, "nothing on screen says " .. what)
  return { "touch", "screen", x + 1, y, 0, player }
end

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
  function() return { "clipboard", "kb000000", " (HUD)", "Aaron" } end,
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
  return { "interrupted" }
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
  return { "interrupted" }
end, { extra = 50, dir = "narrow" })
check(ok and st.paged and st.page2, "many metrics: pages")
check(st.narrow and st.backList, "a narrow screen: the list, then one metric with a way back")
check(M.oob == 0, "it fits a 3 x 4 screen")
M.resize(160, 50)

H.done()
