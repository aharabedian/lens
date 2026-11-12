-- test_hud.lua: the AR glasses HUD, on the Glasses Terminal mock (mocks/glasses.lua, from what lens-discover
-- saw in game): health line, panel bars and values, newest unacknowledged alerts, hiding unused rows, calling
-- setters only for changes, color units, hud.panels, lens-hub drawing it and clearing it on QUIT, and a
-- broken terminal shown on the dashboard instead of stopping the hub.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local hud = require("lens.hub.hud")
local config = require("lens.hub.config")
local glassesMock = require("glasses")

local function model(o)
  local m = {
    now = 100, health = "ok", counts = { bad = 0, warn = 0, unacked = 0 }, alerts = {}, nodes = {},
    panels = {
      { label = "Ore backlog", text = "4.2k", frac = 0.42 },
      { label = "Machines", text = "12/16", frac = 0.75 },
      { label = "Down", text = "1", level = "warn" },
    },
  }
  for k, v in pairs(o or {}) do m[k] = v end
  return m
end

local function opts(o)
  local c = assert(config.check({ hud = o or {}, panels = {} }))
  return c.hud
end

---------------------------------------------------------------- drawing a model
do
  local G = glassesMock.new()
  local h = hud.new(G.proxy, opts())
  h:draw(model())
  check(G.live()[1].kind == "rect" and G.live()[1].alpha == 0.6, "the backdrop is made first, so it's under everything")
  local head = G.find("LENS OK")
  check(head and head.x == 7 and head.y == 6 and head.color[2] > 0.7, "the health line, green, top left")
  local label, value = G.find("Ore bac"), G.find("4.2k")
  check(label and value and value.y == label.y, "a panel row: label and value on one line")
  local bars = {}
  for _, s in ipairs(G.live()) do if s.kind == "rect" and s.y == label.y and s.visible then bars[#bars + 1] = s end end
  check(#bars == 2 and bars[2].w == math.floor(bars[1].w * 0.42 + 0.5), "a bar: background and a fill as wide as the fraction")
  local down = G.find("Down")
  local downValue
  for _, s in ipairs(G.live()) do if s.kind == "text" and s.text == "1" then downValue = s end end
  check(down and downValue and downValue.color[1] > 0.9 and downValue.color[2] > 0.7, "a panel at warn: its value turns yellow")
  local rectsOnDownRow = 0
  for _, s in ipairs(G.live()) do if s.kind == "rect" and s.y == down.y then rectsOnDownRow = rectsOnDownRow + 1 end end
  check(rectsOnDownRow == 0, "a panel without a fraction has no bar")

  local calls = G.calls
  h:draw(model())
  check(G.calls == calls, "drawing the same model again makes no calls at all")

  h:draw(model({ panels = { { label = "Ore backlog", text = "4.3k", frac = 0.43 }, { label = "Machines", text = "12/16", frac = 0.75 },
    { label = "Down", text = "1", level = "warn" } } }))
  check(G.calls - calls <= 3 and G.find("4.3k"), ("a changed value costs only its setters (%d calls)"):format(G.calls - calls))

  local m = model({ health = "bad", counts = { bad = 1, warn = 1, unacked = 2 }, alerts = {
    { key = "a/1", level = "bad", text = "mac2: no power", acked = false },
    { key = "a/2", level = "warn", text = "acked one", acked = true },
    { key = "a/3", level = "warn", text = "idle with work", acked = false },
  } })
  h:draw(m)
  check(G.find("LENS BAD  1 bad  1 warn") and G.find("LENS BAD").color[1] > 0.9, "the health line turns red with counts")
  check(G.find("! mac2: no power") and G.find("· idle with work") and not G.find("acked one"),
    "the newest unacknowledged alerts are listed, bad marked with !")
  check(G.find("! mac2").y > G.find("Down").y, "alerts come after the panels")

  h:draw(model())
  check(not G.find("mac2") and not G.find("idle with work"), "cleared alerts are hidden")
  local n = #G.live()
  h:draw(m)
  check(#G.live() == n, "rows are hidden and shown again, not made again")

  h:clear()
  check(#G.live() == 0, "clear removes every widget it made")
end

---------------------------------------------------------------- options
do
  local G = glassesMock.new()
  hud.new(G.proxy, opts({ colors = "byte" })):draw(model())
  local head = G.find("LENS OK")
  check(head.color[1] == 0x4c and head.color[2] == 0xd1 and head.color[3] == 0x7a and G.live()[1].alpha == 153,
    'colors = "byte": 0..255 colors and alpha')

  G = glassesMock.new()
  hud.new(G.proxy, opts({ x = 100, y = 50, scale = 2 })):draw(model())
  head = G.find("LENS OK")
  check(head.x == 103 and head.y == 52 and head.scale == 2 and G.find("Ore bac").y == 72, "position and scale")

  G = glassesMock.new()
  local c = assert(config.check({ panels = { { label = "A", value = "1" }, { label = "B", value = "2" } }, hud = { panels = { "B" } } }))
  hud.new(G.proxy, c.hud):draw(model({ panels = { { label = "A", text = "1" }, { label = "B", text = "2" } } }))
  check(G.find("B") and not G.find("A "), "hud.panels picks panels by label")
  local _, err = config.check({ panels = { { label = "A", value = "1" } }, hud = { panels = { "Nope" } } })
  check(err == 'hud.panels: no panel labelled "Nope"', "hud.panels must name existing panels")
  _, err = config.check({ hud = { colors = "rgb" } })
  check(err == 'hud.colors must be "float" or "byte"', "hud.colors is checked")
  check(config.check({ hud = false }).hud == false, "hud = false is allowed")
end

---------------------------------------------------------------- in lens-hub
local net = require("net")
local codec = require("lens.codec")
local metrics = require("lens.metrics")

local function runHub(G, cfgText, script)
  M.components = { ["gl000000-0000"] = { type = "glasses", proxy = G.proxy, methods = {} } }
  local path = H.TMP .. "/hud-hub.cfg"
  local f = assert(io.open(path, "w")); f:write(cfgText); f:close()
  local n = net.new()
  M.modem = n:endpoint("hub")
  local ag = n:endpoint("prism-ore")
  ag.open(4243)
  local m = metrics.new{ role = "prism", clock = function() return M.time end }
  local enc = codec.encoder{ node = "prism-ore", role = "prism", boot = 3, interval = 5 }
  m:gauge("prism_backlog_items", "b"):set(4200)
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
  io.stderr = { write = function(_, s) written[#written + 1] = s end }
  local ok, err = pcall(H.run, "lens-hub.lua", path)
  io.stderr = realStderr
  M.onPull = nil
  M.components = {}
  return ok and #written == 0, err or table.concat(written)
end

do
  M.setTime(0)
  local G = glassesMock.new()
  local s = {}
  local ok, err = runHub(G, [[return { panels = { { label = "Ore", value = "prism_backlog_items", max = 10000 } } }]], function(t)
    if t >= 4 and not s.seen then
      s.seen = true
      s.head = G.find("LENS OK") ~= nil
      s.ore = G.find("4.2k") ~= nil
      s.calls = G.calls
      return nil
    end
    if s.seen and t >= 8 and not s.quiet then
      s.quiet = true
      s.perTick = (G.calls - s.calls) / 4
      return { "touch", "screen", M.find(" QUIT ") + 1, 1, 0, "p" }
    end
    if t > 20 then return { "interrupted" } end
  end)
  check(ok, "lens-hub runs with a Glasses Terminal" .. (ok and "" or (": " .. tostring(err))))
  check(s.head and s.ore, "lens-hub draws the HUD: health and panels")
  check(s.perTick == 0, ("nothing changing: no calls to the terminal (%.1f per second)"):format(s.perTick or -1))
  check(#G.live() == 0, "QUIT removes the HUD's widgets")
end

do
  M.setTime(0)
  local G = glassesMock.new()
  G.proxy.addRect = function() error("terminal unloaded") end
  local s = {}
  local ok, err = runHub(G, "return {}", function(t)
    if t >= 3 and not s.seen then
      s.seen = true
      s.footer = M.row(M.H)
      s.dash = M.find("prism-ore") ~= nil
      return { "interrupted" }
    end
  end)
  check(ok, "a broken Glasses Terminal doesn't stop the hub" .. (ok and "" or (": " .. tostring(err))))
  check(s.dash and s.footer:find("HUD: ", 1, true) and s.footer:find("terminal unloaded", 1, true),
    "the dashboard keeps working and shows the HUD's error in its footer")
end

do
  M.setTime(0)
  local G = glassesMock.new()
  local ok = runHub(G, "return { hud = false }", function(t) if t >= 3 then return { "interrupted" } end end)
  check(ok and G.calls == 0, "hud = false: the terminal is left alone")
end

H.done()
