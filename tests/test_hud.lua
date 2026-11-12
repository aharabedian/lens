-- test_hud.lua: the AR glasses HUD on one Glasses Terminal mock (mocks/glasses.lua, from what was measured in
-- game): health strip, bars, newest unacknowledged alerts, nothing overlapping, setters only on change, the call
-- count, options, blocks from nine anchors with bar / text / gap / alerts elements, lens-hub drawing it (and its
-- calls per minute on the dashboard), clearing on QUIT, and a broken terminal shown on the dashboard instead of
-- stopping the hub. (A HUD per player and the HUD editor: test_huds.) Previews: make screens.
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

-- The layout tests below were written for one block of bars then alerts: a HUD whose draw takes
-- model.hudBars and places the block as the checked config's first block (with its alerts count).
local function newHud(proxy, o)
  local h = hud.new(proxy, o)
  local draw = h.draw
  function h.draw(self, m)
    if not m.hudBlocks then
      local b = (o.blocks or {})[1] or {}
      local count = 3
      for _, el in ipairs(b.elements or {}) do if el.kind == "alerts" then count = el.count end end
      local items = {}
      for _, bar in ipairs(m.hudBars or {}) do items[#items + 1] = setmetatable({ kind = "bar" }, { __index = bar }) end
      items[#items + 1] = { kind = "alerts", count = count }
      m = setmetatable({ hudBlocks = { { anchor = b.anchor, x = b.x, y = b.y, width = b.width, items = items } } },
        { __index = m })
    end
    return draw(self, m)
  end
  return h
end

local function opts(o)
  o = o or {}
  if o.anchor == nil then o.anchor, o.x, o.y = "top-left", o.x or 4, o.y or 20 end   -- the layout tests' frame
  return assert(config.check({ hud = o })).hud
end
local function texts(G)
  local out = {}
  for _, s in ipairs(G.live()) do if s.kind == "text" and s.visible then out[#out + 1] = s end end
  return out
end

---------------------------------------------------------------- the layout
do
  local G = glassesMock.new()
  local h = newHud(G.proxy, opts())
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

---------------------------------------------------------------- anchors
do
  local G = glassesMock.new()
  local h = newHud(G.proxy, assert(config.check({})).hud)
  h:draw(model())
  local bg = G.live()[1]
  check(bg.x == 854 - 4 - 160 and bg.y == 4, "by default the block sits top-right, 4 from the edges of an 854-wide view")
  h:draw(model({ screen = { w = 1000, h = 500 } }))
  check(bg.x == 1000 - 4 - 160 and G.find("Ore").x == bg.x + 6, "a wider view (from glasses_on) moves it, rows and all")

  G = glassesMock.new()
  newHud(G.proxy, opts({ anchor = "bottom-left", x = 10, y = 10 })):draw(model({ screen = { w = 800, h = 400 } }))
  bg = G.live()[1]
  check(bg.x == 10 and bg.y + bg.h == 390, "bottom-left: x and y are margins from the left and bottom")
  local _, err = config.check({ hud = { anchor = "middle" } })
  check(err and err:find("hud.anchor must be", 1, true), "anchor is checked")
end

---------------------------------------------------------------- options and config
do
  local G = glassesMock.new()
  newHud(G.proxy, opts({ colors = "byte" })):draw(model())
  check(G.live()[2].color[1] == 0x4f and G.live()[1].alpha == 89, 'colors = "byte": 0..255 colors and alpha')

  G = glassesMock.new()
  newHud(G.proxy, opts({ x = 100, y = 50, scale = 2, width = 320 })):draw(model())
  local label = G.find("Ore")
  check(label.x == 106 and label.y == 52 and label.scale == 2 and G.live()[1].w == 320, "position, scale and width")

  G = glassesMock.new()
  newHud(G.proxy, opts({ alpha = 0 })):draw(model())
  check(not G.live()[1].visible, "alpha = 0: no backdrop")

  local c = assert(config.check({ hud = { bars = { { label = "Ore", value = "sum(prism_backlog_items)", max = 2e6 } } } }))
  local el = c.hud.blocks[1].elements[1]
  check(el.kind == "bar" and el.label == "Ore" and el.max == 2e6 and c.hud.blocks[1].anchor == "top-right"
    and c.hud.bars == nil, "hud.bars take the panel form, and become the first block's elements")
  local _, err = config.check({ hud = { bars = { { label = "Ore", value = "sum(x" } } } })
  check(err and err:find("hud.bar 1 (Ore): value: expected )", 1, true), "a bad bar query is named")
  _, err = config.check({ hud = { alpha = 2 } })
  check(err == "hud.alpha must be 0..1", "alpha is checked")
  check(config.check({ hud = false }).hud == false, "hud = false is allowed")
end

---------------------------------------------------------------- blocks
-- Several blocks from their anchors, each with bar, text, gap and alerts elements.
local function blockModel(blocks, extra)
  local m = model({ hudBlocks = blocks, screen = { w = 800, h = 400 } })
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
  local first = G.find("Sifter down")
  check(first and first.y - value.y == 11 + 5 and G.find("two") and not G.find("three") and G.find("+1 more"),
    "a gap is half a row; alerts show their count, then +N more")
  local ore = G.find("Ore")
  local bg2
  for _, s in ipairs(live) do if s.kind == "rect" and s.w == 120 then bg2 = s end end
  check(bg2 and bg2.x == 400 - 60 and math.abs((bg2.y + bg2.h / 2) - 200) <= 1 and ore.y > bg2.y,
    "center: in the middle of the view")
  local okText = G.find("LENS OK")
  check(okText and okText.x > 800 - 100 - 10 and okText.y > 300, "an empty block: LENS OK, in its corner")
  local calls = h.calls
  h:draw(blockModel({ { anchor = "top", x = 0, y = 4, width = 160,
    items = { { kind = "text", label = "Net 5m", text = "+2.4k EU/t" } } } }))
  check(not G.find("Sifter down") and not G.find("LENS OK") and not G.find("Power") and h.calls > calls,
    "blocks and elements that go away are hidden")
  h:draw(blockModel({ { anchor = "top-left", x = -500, y = 9000, width = 160, items = {} } }))
  local bg = G.live()[1]
  check(bg.x == 0 and bg.y + bg.h <= 400, "a block nudged off the view stays on it")
end

---------------------------------------------------------------- in lens-hub
local R = require("hubrun")(H)
local PRISM = R.agent{ node = "prism-ore", role = "prism", setup = function(m)
  m:gauge("prism_backlog_items", "b"):set(1240000)
end }

local function runHub(G, cfgText, script)
  return R.run{ cfg = cfgText, agents = { PRISM }, terminals = { ["gl000000-0000"] = G }, script = script }
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
    if s.seen and not s.moved then
      s.moved = true
      s.x = G.live()[1].x
      return { "glasses_on", "gl000000-0000", "Aaron", 1200, 600 }
    end
    if s.moved and not s.movedSeen then
      s.movedSeen = true
      s.x2 = G.live()[1].x
      s.calls = G.calls
      return nil
    end
    if s.movedSeen and t >= 70 and not s.quiet then
      s.quiet = true
      s.perMinute = (G.calls - s.calls) / (t - 4) * 60
      s.footer = M.row(M.H)
      return { "touch", "screen", M.find(" QUIT ") + 1, 1, 0, "p" }
    end
    if t > 90 then return { "interrupted" } end
  end)
  check(ok, "lens-hub runs with a Glasses Terminal" .. (ok and "" or (": " .. tostring(err))))
  check(s.bar, "lens-hub draws hud.bars")
  check(s.x == 854 - 164 and s.x2 == 1200 - 164, "a glasses_on with a new GUI size moves the HUD to its corner")
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
