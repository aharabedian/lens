-- test_hud.lua: the AR glasses HUD on the Glasses Terminal mock (mocks/glasses.lua, from what was measured in
-- game): health strip, hud.bars, newest unacknowledged alerts, nothing overlapping, setters only on change,
-- the call count, options, lens-hub drawing it (and its calls per minute on the dashboard), clearing on QUIT,
-- and a broken terminal shown on the dashboard instead of stopping the hub. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local hud = require("lens.hub.hud")
local config = require("lens.hub.config")
local glassesMock = require("glasses")
local P = hud.COLORS

local function near(color, hex)
  local r, g, b = hud.rgb(hex, "float")
  return math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6 and math.abs(color[3] - b) < 1e-6
end

local ORE = { { label = "Ore", text = "1.2M", frac = 0.62 } }
local function model(o)
  local m = { now = 100, health = "ok", counts = { bad = 0, warn = 0, unacked = 0 }, alerts = {}, nodes = {},
    panels = {}, hudBars = ORE }
  for k, v in pairs(o or {}) do m[k] = v end
  return m
end
local ALERTS = {
  { key = "a/1", level = "bad", text = "Large Sifter: no power", acked = false },
  { key = "a/2", level = "warn", text = "acked one", acked = true },
  { key = "a/3", level = "warn", text = "Washer B idle 2m with work waiting", acked = false },
}

local function opts(o) return assert(config.check({ hud = o or {} })).hud end
local function texts(G)
  local out = {}
  for _, s in ipairs(G.live()) do if s.kind == "text" and s.visible then out[#out + 1] = s end end
  return out
end

---------------------------------------------------------------- the layout
do
  local G = glassesMock.new()
  local h = hud.new(G.proxy, opts())
  h:draw(model())
  local bg, strip = G.live()[1], G.live()[2]
  check(bg.kind == "rect" and strip.kind == "rect" and bg.x == 4 and bg.y == 20 and bg.w == 160 and bg.alpha == 0.35,
    "a faint backdrop, made first so it's underneath, at (4, 20), 160 wide")
  check(strip.w == 2 and strip.h == bg.h and near(strip.color, P.ok), "a thin strip down the left in the health's color")
  local label, value = G.find("Ore"), G.find("1.2M")
  check(label and value and label.y == value.y and near(label.color, P.dim) and near(value.color, P.text),
    "one bar row: dim label, white value")
  local track, fill
  for _, s in ipairs(G.live()) do
    if s.kind == "rect" and s ~= bg and s ~= strip and s.visible then
      if near(s.color, P.track) then track = s elseif near(s.color, P.fill) then fill = s end
    end
  end
  check(track and fill and fill.w == math.floor(track.w * 0.62 + 0.5) and track.w > track.h * 5,
    "the bar: a dark track and a teal fill as wide as the fraction, wide and short")
  check(label.x + G.textWidth(label) <= track.x and track.x + track.w <= value.x
    and value.x + G.textWidth(value) <= bg.x + bg.w, "label, bar and value don't overlap or leave the backdrop")
  check(not G.find("LENS"), "no title line when there's a bar")
  H.glasses("hud-quiet", G)

  local calls = h.calls
  h:draw(model())
  check(h.calls == calls and G.calls == calls, "drawing the same state again costs no calls (h.calls counts them)")

  h:draw(model({ hudBars = { { label = "Ore", text = "1.3M", frac = 0.64 } } }))
  check(h.calls - calls == 2 and G.find("1.3M"), "a new value costs two calls: the text and the fill's size")

  local m = model({ health = "bad", alerts = ALERTS, counts = { bad = 1, warn = 2, unacked = 2 },
    hudBars = { { label = "Ore", text = "1.3M", frac = 0.95, level = "bad" } } })
  h:draw(m)
  local bang = G.find("!")
  check(G.find("Large Sifter: no power") and G.find("Washer B idle") and not G.find("acked one"),
    "unacknowledged alerts are listed after the bars")
  check(bang and near(bang.color, P.bad) and near(G.find("Large Sifter").color, P.text),
    "an alert: a colored ! and white text")
  check(near(strip.color, P.bad) and near(G.find("1.3M").color, P.bad), "health bad: the strip turns red; a bad bar's value too")
  local fits = true
  for _, s in ipairs(texts(G)) do if s.x + G.textWidth(s) > bg.x + bg.w then fits = false end end
  check(fits, "long alert texts are cut to fit")
  H.glasses("hud-alerts", G)

  local five = {}
  for i = 1, 5 do five[i] = { key = "k" .. i, level = "warn", text = "alert " .. i, acked = false } end
  h:draw(model({ alerts = five }))
  check(G.find("alert 3") and not G.find("alert 4") and G.find("+2 more"), "three alerts, then +N more")

  h:draw(model({ hudBars = {}, alerts = {} }))
  check(G.find("LENS OK") and not G.find("Ore") and not G.find("alert 1"), "nothing to show: just LENS OK")
  H.glasses("hud-empty", G)

  h:clear()
  check(#G.live() == 0, "clear removes every widget it made")
end

---------------------------------------------------------------- options and config
do
  local G = glassesMock.new()
  hud.new(G.proxy, opts({ colors = "byte" })):draw(model())
  check(G.live()[2].color[1] == 0x4f and G.live()[1].alpha == 89, 'colors = "byte": 0..255 colors and alpha')

  G = glassesMock.new()
  hud.new(G.proxy, opts({ x = 100, y = 50, scale = 2, width = 320 })):draw(model())
  local label = G.find("Ore")
  check(label.x == 106 and label.y == 52 and label.scale == 2 and G.live()[1].w == 320, "position, scale and width")

  G = glassesMock.new()
  hud.new(G.proxy, opts({ alpha = 0 })):draw(model())
  check(not G.live()[1].visible, "alpha = 0: no backdrop")

  local c = assert(config.check({ hud = { bars = { { label = "Ore", value = "sum(prism_backlog_items)", max = 2e6 } } } }))
  check(#c.hud.bars == 1 and c.hud.y == 20, "hud.bars take the panel form")
  local _, err = config.check({ hud = { bars = { { label = "Ore", value = "sum(x" } } } })
  check(err and err:find("hud.bar 1 (Ore): value: expected )", 1, true), "a bad bar query is named")
  _, err = config.check({ hud = { alpha = 2 } })
  check(err == "hud.alpha must be 0..1", "alpha is checked")
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
  m:gauge("prism_backlog_items", "b"):set(1240000)
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
  local cfg = [[return { hud = { bars = { { label = "Ore", value = "sum(prism_backlog_items)", max = 2000000 } } } }]]
  local ok, err = runHub(G, cfg, function(t)
    if t >= 4 and not s.seen then
      s.seen = true
      s.bar = G.find("1.2M") ~= nil and G.find("Ore") ~= nil
      s.calls = G.calls
      return nil
    end
    if s.seen and t >= 70 and not s.quiet then
      s.quiet = true
      s.perMinute = (G.calls - s.calls) / (t - 4) * 60
      s.footer = M.row(M.H)
      return { "touch", "screen", M.find(" QUIT ") + 1, 1, 0, "p" }
    end
    if t > 90 then return { "interrupted" } end
  end)
  check(ok, "lens-hub runs with a Glasses Terminal" .. (ok and "" or (": " .. tostring(err))))
  check(s.bar, "lens-hub draws hud.bars")
  check(s.perMinute == 0, ("nothing changing: no calls to the terminal (%.1f a minute)"):format(s.perMinute or -1))
  check(s.footer and s.footer:find("HUD 0 calls/min", 1, true), "the dashboard shows the HUD's calls per minute")
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
