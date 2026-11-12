-- test_elements.lua: what a view can show, through lens-hub: state dots (one per machine), several values in
-- one line (text templates), and views shown only while their `when` is true, on the dashboard, in the HUD
-- and in the view editor's preview. (format, query.select and the checks on their own: test_hub.)
-- Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local hud = require("lens.hub.hud")
local glassesMock = require("glasses")
local P = hud.COLORS

local function near(color, hex)
  local r, g, b = hud.rgb(hex, "float")
  return math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6 and math.abs(color[3] - b) < 1e-6
end

-- An ore line whose third machine goes down at t = 20, and an LSC that starts draining at t = 20.
local function agents()
  local ore = R.agent{ node = "prism-ore", role = "prism", setup = function(m)
    m:gauge("prism_machine_state", "state")
  end, cycle = function(m, now)
    m:gauge("prism_backlog_items", "backlog", "items"):set(4200, { process = "ore" })
    local state = m:gauge("prism_machine_state", "state")
    for i = 1, 4 do
      local st = (i == 3 and now >= 20) and "down" or (i == 4 and "idle" or "running")
      for _, s in ipairs({ "running", "idle", "down" }) do
        state:set(s == st and 1 or 0, { process = "ore", machine = "mac" .. i, state = s })
      end
    end
  end }
  local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m, now)
    m:gauge("lumen_stored_eu", "s", "EU"):set(10773450724, { lsc = "Main" })
    m:gauge("lumen_capacity_eu", "c", "EU"):set(11340000000, { lsc = "Main" })
    m:gauge("lumen_net_5m_eut", "n", "EU/t"):set(now >= 20 and -1100 or 2400, { lsc = "Main" })
  end }
  return { ore, power }
end

local CFG = [[return {
  panels = {
    { label = "Ore line", dots = 'prism_machine_state{node="prism-ore"}' },
    { label = "LSC", text = "{s} / {c} EU", values = { s = "sum(lumen_stored_eu)", c = "sum(lumen_capacity_eu)" } },
    { label = "Draining", value = "lumen_net_5m_eut", unit = "EU/t", format = "signed", color = "sign",
      when = "lumen_net_5m_eut < 0" },
  },
  hud = { blocks = { { anchor = "top-right", elements = {
    { kind = "text", label = "Ore", dots = 'prism_machine_state{node="prism-ore"}' },
    { kind = "text", label = "Backlog", value = 'sum(prism_backlog_items{node="prism-ore"})', unit = "items",
      status = {
        { "bad", 'sum(prism_machine_state{node="prism-ore", state="down"}) > 0' },
        { "warn", "$value > 50000" },
        { "good", 'sum(prism_machine_state{node="prism-ore", state="running"}) > 0' } } },
    { kind = "text", label = "Smelt", status = { { "good", 'sum(prism_machine_state{node="prism-smelt"}) > 0' } } },
    { kind = "text", label = "LSC", text = "{s} / {c}", values = { s = "sum(lumen_stored_eu)", c = "sum(lumen_capacity_eu)" } },
    { kind = "text", label = "Net", value = "lumen_net_5m_eut", format = "signed", color = "sign", when = "lumen_net_5m_eut < 0" },
  } } } },
}]]

M.setTime(0)
M.resize(160, 50)
local G = glassesMock.new()
G.proxy.getBindPlayers = function() return "Aaron" end
local seen = {}
local ok, err = R.run{ cfg = CFG, agents = agents(), keyboard = true, terminals = { ["gl-a"] = G }, script = function(t)
  if t >= 8 and not seen.before then
    seen.before = true
    local lx, ly = M.find("Ore line", 3)           -- its dots are on the row below (NODES has dots too)
    local dx, dy = lx, ly + 1
    local dots = {}
    for x = dx, dx + 6, 2 do dots[#dots + 1] = M.fgAt(x, dy) end
    seen.dots = M.row(dy):sub(1):find("●", 1, true) and dots[1] == 0x4cd17a and dots[2] == 0x4cd17a and dots[3] == 0x4cd17a
      and dots[4] == 0x7d8a96
    seen.template = M.find("10.8G / 11.3G EU", 3) ~= nil
    seen.hiddenDash = not M.find("Draining", 3)
    seen.hudDots, seen.hudHidden = 0, not G.find("Net")
    local backlogLabel, backlogValue = G.find("Backlog"), G.find("4.2k items")
    for _, s in ipairs(G.live()) do
      if s.kind == "text" and s.text == "●" and s.visible then
        if s.y == backlogLabel.y then
          seen.oneDot = (seen.oneDot or 0) + 1
          seen.green = near(s.color, P.good)
        elseif s.y == G.find("Ore").y then
          seen.hudDots = seen.hudDots + 1
        end
      end
    end
    seen.sameRow = backlogValue and backlogValue.y == backlogLabel.y
    local smelt = G.find("Smelt")
    for _, s in ipairs(G.live()) do
      if s.text == "●" and s.visible and s.y == smelt.y then seen.gray = near(s.color, P.off) end
    end
    seen.hudTemplate = G.find("10.8G / 11.3G") ~= nil
    return nil
  end
  if t >= 26 and not seen.after then
    seen.after = true
    local dx, dy = M.find("Ore line", 3)
    seen.down = M.fgAt(dx + 4, dy + 1) == 0xff5c5c
    local _, ry = M.find("Draining", 3)
    seen.shown = ry and M.find("-1.1k EU/t", ry)
    local net = G.find("-1.1k")
    seen.hudShown = net and near(net.color, P.bad)
    local red
    local row = G.find("Backlog").y
    for _, s in ipairs(G.live()) do
      if s.text == "●" and s.visible and near(s.color, P.bad) then
        if s.y == row then seen.lineRed = true elseif s.y == G.find("Ore").y then red = true end
      end
    end
    seen.hudDown = red
    H.screen("elements")
    H.glasses("hud-elements", G)
    return R.tap(" EDIT ", "Aaron", 1)
  end
  if seen.after and not seen.editing then
    seen.editing = true
    return R.tap("+ NEW", "Aaron", 3)
  end
  if seen.editing and not seen.typed then
    seen.typed = true
    local _, ty = M.find("Text", 3)
    R.queue({ "touch", "screen", 20, ty, 0, "Aaron" }, R.keys("{s} EU", "Aaron"))
    local _, vy = M.find("Values", 3)
    R.queue({ "touch", "screen", 20, vy, 0, "Aaron" }, R.paste("s=sum(lumen_stored_eu)", "Aaron"))
    local _, ly = M.find("Label", 3)
    R.queue({ "touch", "screen", 20, ly, 0, "Aaron" }, R.keys("Stored", "Aaron"))
    return nil
  end
  if seen.typed and not seen.preview then
    seen.preview = M.find("Now", 3) and M.find("10.8G EU", 3)
    H.screen("view-editor-template")
    return "stop"
  end
  if t > 200 then return "stop" end
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.dots, "dots: one per machine, green while running, dim while idle")
check(seen.down, "a machine that goes down turns its dot red")
check(seen.template, "several values in one line: {s} / {c} EU")
check(seen.hiddenDash and seen.shown, "a panel with when shows only while it's true")
check(seen.hudDots == 4 and seen.hudDown, "the HUD: a dot per machine, red when down")
check(seen.hudTemplate, "the HUD: several values in one line")
check(seen.oneDot == 1 and seen.green and seen.sameRow, "status rules: one dot, green while a machine runs, the backlog beside it")
check(seen.lineRed, "red once a machine is down (the first rule)")
check(seen.gray, "no rule true: gray (off)")
check(seen.hudHidden and seen.hudShown, "the HUD: an element with when appears only while it's true, colored")
check(seen.preview, "the view editor: a template typed in, previewed with its values")

-- Status rules made in the view editor: + RULE, tap the color to cycle it, type the query; fix a typo with
-- the cursor (tap into the text, ←, Delete); order with ▲; SAVE.
M.setTime(0)
M.resize(160, 50)
local K = require("lens.hub.textfield").KEYS
local files = require("lens.files")
local rs = {}
local rstep = 0
local dir
ok, err, dir = R.run{ cfg = "return {}", dir = "rules", agents = agents(), keyboard = true, script = function(t)
  if t < 3 then return nil end
  rstep = rstep + 1
  if rstep == 1 then return R.tap(" EDIT ", "Aaron", 1) end
  if rstep == 2 then return R.tap("+ NEW", "Aaron", 3) end
  if rstep == 3 then
    R.queue(R.keys("Ore", "Aaron"))
    R.queue(R.key(K.enter, "Aaron"))                         -- to Query
    R.queue(R.keys('sum(prism_backlog_items{node="prism-ore"})', "Aaron"))
    return nil
  end
  if rstep == 4 then rs.empty = M.find("none: no status dot", 3) ~= nil; return R.tap("+ RULE", "Aaron", 3) end
  if rstep == 5 then
    rs.row = M.find("first true", 3) and M.find(" good ", 3)
    R.queue(R.keys('sum(prism_machine_state{node="prism-ore", state="runnning"}) > 0', "Aaron"))   -- a typo
    return nil
  end
  if rstep == 6 then
    -- Tap just after "runnn" and delete one n: the cursor goes where the tap is.
    local x, y = M.find("runnning", 3)
    return { "touch", "screen", x + 5, y, 0, "Aaron" }
  end
  if rstep == 7 then R.queue(R.key(K.back, "Aaron")); return nil end
  if rstep == 8 then
    rs.fixed = M.find('state="running"}) > 0', 3) ~= nil
    return R.tap("+ RULE", "Aaron", 3)
  end
  if rstep == 9 then
    R.queue(R.keys('sum(prism_machine_state{node="prism-ore", state="down"}) > 0', "Aaron"))
    return nil
  end
  if rstep == 10 then
    local _, y = M.find('state="down"', 3)
    rs.chipY = y
    return { "touch", "screen", M.find(" good ", y), y, 0, "Aaron" }   -- good -> warn
  end
  if rstep == 11 then return { "touch", "screen", M.find(" warn ", rs.chipY), rs.chipY, 0, "Aaron" } end   -- -> bad
  if rstep == 12 then
    rs.bad = M.find(" bad  ", rs.chipY) ~= nil
    return { "touch", "screen", M.find("▲", rs.chipY), rs.chipY, 0, "Aaron" }    -- the down rule first
  end
  if rstep == 13 then
    local _, dy = M.find('state="down"', 3)
    local _, ry = M.find('state="running"', 3)
    rs.ordered = dy < ry
    H.screen("view-editor-rules")
    return R.tap("SAVE", "Aaron", 1)
  end
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(rs.empty and rs.row, "+ RULE adds a row: a color chip and a query, typed into")
check(rs.fixed, "a tap puts the cursor in the text; Backspace there fixes a typo")
check(rs.bad and rs.ordered, "tapping the chip cycles its color; ▲ orders the rules")
local saved = files.loadTable(dir .. "/lens-board.cfg")
local st = saved and saved.views[1] and saved.views[1].status
check(st and #st == 2 and st[1][1] == "bad" and st[1][2]:find('state="down"', 1, true) and st[2][1] == "good"
  and st[2][2]:find('state="running"', 1, true), "SAVE: the rules, in order, in lens-board.cfg")

-- The view editor, now with 16 fields, fits a tier 2 screen.
M.setTime(0)
M.resize(80, 25)
M.oob = 0
local step = 0
ok = R.run{ cfg = CFG, dir = "tier2", agents = agents(), keyboard = true, script = function(t)
  if t < 6 then return nil end
  step = step + 1
  if step == 1 then return R.tap(" EDIT ", "Aaron", 1) end
  if step == 2 then return R.tap("EDIT", "Aaron", 4) end
  seen.tier2 = M.find("Show when", 3) and M.find("Now", 3) and M.find("SAVE", 1)
  H.screen("view-editor-tier2")
  return "stop"
end }
check(ok and seen.tier2 and M.oob == 0, "the view editor fits a tier 2 screen")
M.resize(160, 50)

H.done()
