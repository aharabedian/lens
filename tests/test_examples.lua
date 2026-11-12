-- test_examples.lua: the views in docs/examples.md, as panels in lens-hub, against a PRISM ore line and a LUMEN
-- power room: each shows what the doc says it does. (That every example loads: test_layout.)
-- Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check

-- The views in docs/examples.md (blocks starting with { label = ...), in order, as one panels list.
local doc = assert(io.open(H.ROOT .. "/docs/examples.md")):read("*a")
local views = {}
for block in doc:gmatch("```lua\n(.-)```") do
  if block:find("^%s*{%s*label%s*=") then
    -- Drop a trailing comment and comma, so the blocks join into one list.
    views[#views + 1] = (block:gsub("%s*%-%-[^\n]*%s*$", ""):gsub("%s*,%s*$", ""))
  end
end
check(#views >= 12, ("docs/examples.md has its views (%d)"):format(#views))
local CFG = "return { panels = { " .. table.concat(views, ",\n") .. " } }"

-- An ore line: 3 running, 1 idle, 1 down; a backlog, progress, 2 item types with no rule, slow scans.
-- A power room: two LSCs, Spare unreadable; draining (2.5 hours left at the hour's average).
local ore = R.agent{ node = "prism-ore", role = "prism", cycle = function(m)
  m:beginCycle()
  m:gauge("prism_backlog_items", "b", "items"):set(4200, { process = "ore" })
  m:gauge("prism_unassigned_types", "u"):set(2)
  m:gauge("prism_scan_seconds", "s", "s"):set(2.5)
  local states = { "running", "running", "running", "idle", "down" }
  for i, st in ipairs(states) do
    for _, s in ipairs({ "running", "idle", "down" }) do
      m:gauge("prism_machine_state", "st"):set(s == st and 1 or 0, { process = "ore", machine = "m" .. i, state = s })
    end
    m:gauge("prism_machine_progress_ratio", "p"):set(st == "running" and 0.5 or 0, { process = "ore", machine = "m" .. i })
  end
end }
local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m)
  m:beginCycle()
  m:gauge("lumen_lsc_up", "u"):set(1, { lsc = "Main" })
  m:gauge("lumen_lsc_up", "u"):set(0, { lsc = "Spare" })
  m:gauge("lumen_stored_eu", "s", "EU"):set(9e9, { lsc = "Main" })
  m:gauge("lumen_capacity_eu", "c", "EU"):set(1e10, { lsc = "Main" })
  m:gauge("lumen_input_eut", "i", "EU/t"):set(66000, { lsc = "Main" })
  m:gauge("lumen_output_eut", "o", "EU/t"):set(65000, { lsc = "Main" })
  m:gauge("lumen_net_5m_eut", "n", "EU/t"):set(-1100, { lsc = "Main" })
  m:gauge("lumen_net_1h_eut", "n", "EU/t"):set(-2000, { lsc = "Main" })
  m:gauge("lumen_drain_seconds", "d", "s"):set(9000, { lsc = "Main" })
end }

M.setTime(0)
M.resize(160, 50)
local seen = {}
local ok, err = R.run{ cfg = CFG, agents = { ore, power }, script = function(t)
  if t < 8 then return nil end
  H.screen("examples")
  local function color(text, dx)
    local x, y = M.find(text, 3)
    return x and M.fgAt(x + (dx or 0), y)
  end
  local function dotBefore(label)                   -- a status dot leads its panel's label
    local x, y = M.find(label, 3)
    return x and M.fgAt(x - 2, y)
  end
  local RED, YELLOW, GREEN = 0xff5c5c, 0xffd24c, 0x4cd17a
  seen.ore = M.find("4.2k items", 3) and dotBefore("Ore ") == RED
  seen.machines = M.find("3/5 running", 3) ~= nil
  seen.progress = M.find("30%", 3) ~= nil
  seen.noRule = M.find("2 item types", 3) and dotBefore("No rule") == YELLOW
  seen.scan = color("2.5 s") == YELLOW
  seen.power = M.find("90%", 3) and dotBefore("Power") == YELLOW
  seen.flow = M.find("66k in 65k out EU/t", 3) ~= nil
  seen.net = color("-1.1k EU/t") == RED
  seen.empty = M.find("Empty in", 3) and color("2h 30m") == YELLOW
  seen.full = not M.find("Full in", 3)
  local lx, ly = M.find("LSCs", 3)
  seen.lscs = lx and M.fgAt(lx, ly + 1) == GREEN and M.fgAt(lx + 2, ly + 1) == RED
  seen.base = M.find("9G power, 4.2k ore", 3) and dotBefore("Base") == RED
  seen.lowPower = not M.find("Ore on low power", 3)
  seen.green = GREEN
  return "stop"
end }
check(ok, "lens-hub runs every example" .. (ok and "" or (": " .. tostring(err))))
check(seen.ore, "Ore: the backlog, red while a machine is down")
check(seen.machines, "Ore machines: 3/5 running")
check(seen.progress, "Progress: the machines' average")
check(seen.noRule, "No rule: 2 item types, yellow")
check(seen.scan, "Scan: yellow over 2 s")
check(seen.power, "Power: 90%, yellow while draining toward empty within 4 hours")
check(seen.flow, "Flow: in and out on one line")
check(seen.net, "Net 5m: red below zero")
check(seen.empty, "Empty in: shown while draining, 2h 30m, yellow")
check(seen.full, "Full in: hidden while not charging")
check(seen.lscs, "LSCs: a dot each, red for the one that can't be read")
check(seen.base, "Base: red, because an LSC is down")
check(seen.lowPower, "Ore on low power: hidden while power is above 25%")

H.done()
