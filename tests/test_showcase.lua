-- test_showcase.lua: a busy base on lens-hub (showcase-*.png, for the README and the website): three PRISM routers,
-- a LUMEN power room and your own program reporting, a full dashboard with live alerts, and a HUD block with
-- bars, dots on the left and alerts. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local glassesMock = require("glasses")

-- The ore line: ten machines, Centrifuge B idle with work waiting.
local ORE = {
  { "Macerator", "crush" }, { "Washer A", "wash" }, { "Washer B", "wash" }, { "Washer C", "wash" },
  { "Thermal A", "thermal" }, { "Thermal B", "thermal" }, { "Centrifuge A", "centrifuge" },
  { "Centrifuge B", "centrifuge", "idle" }, { "Sifter", "sift" }, { "Chem Bath", "chembath" },
}
local BACKLOG = { crush = 1920, wash = 8959, thermal = 2775, centrifuge = 3545, sift = 112, chembath = 96 }
local function states(m, list)
  local state, progress = m:gauge("prism_machine_state", "state"), m:gauge("prism_machine_progress_ratio", "p")
  for i, mc in ipairs(list) do
    local st = mc[3] or "running"
    for _, s in ipairs({ "running", "idle", "down" }) do
      state:set(s == st and 1 or 0, { process = mc[2], machine = mc[1], state = s })
    end
    progress:set(st == "running" and (i * 17 % 90 + 8) / 100 or 0, { process = mc[2], machine = mc[1] })
  end
end
-- Readings drift over a few minutes, so the panels' sparklines have a shape.
local function drift(now, phase, amount) return 1 + amount * math.sin(now / 25 + phase) end
local ore = R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
  m:beginCycle()
  local i = 0
  for p, n in pairs(BACKLOG) do
    i = i + 1
    m:gauge("prism_backlog_items", "b", "items"):set(math.floor(n * drift(now, i, 0.25)), { process = p })
  end
  m:gauge("prism_unassigned_types", "u"):set(0)
  m:gauge("prism_scan_seconds", "s", "s"):set(0.4)
  states(m, ORE)
  m:alert("idle:Centrifuge B", "warn", ("Centrifuge B idle %dm with work waiting"):format(math.max(1, now // 60)))
end }

-- The smelting line: four EBFs, EBF 3 without power.
local SMELT = { { "EBF 1", "ebf" }, { "EBF 2", "ebf" }, { "EBF 3", "ebf", "down" }, { "EBF 4", "ebf" } }
local smelt = R.agent{ node = "prism-smelt", role = "prism", cycle = function(m, now)
  m:beginCycle()
  m:gauge("prism_backlog_items", "b", "items"):set(math.floor(1024 * drift(now, 2, 0.4)), { process = "ebf" })
  m:gauge("prism_scan_seconds", "s", "s"):set(0.3)
  states(m, SMELT)
  m:alert("down:EBF 3", "bad", "EBF 3: no power")
end }

-- The sifting line on a third router: all running.
local GEMS = { { "Sifter A", "sift" }, { "Sifter B", "sift" }, { "Sifter C", "sift" } }
local gems = R.agent{ node = "prism-gems", role = "prism", cycle = function(m, now)
  m:beginCycle()
  m:gauge("prism_backlog_items", "b", "items"):set(math.floor(640 * drift(now, 4, 0.3)), { process = "sift" })
  m:gauge("prism_scan_seconds", "s", "s"):set(0.2)
  states(m, GEMS)
end }

-- Three LSCs, filling overall; Spare low.
local LSC = { Main = { 10.77e9, 11.34e9 }, Backup = { 3.0e9, 4.0e9 }, Spare = { 0.4e9, 4.0e9 } }
local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m, now)
  m:beginCycle()
  local i = 0
  for name, v in pairs(LSC) do
    i = i + 1
    local stored = math.min(v[2], v[1] * drift(now, i, 0.03))
    m:gauge("lumen_lsc_up", "u"):set(1, { lsc = name })
    m:gauge("lumen_stored_eu", "s", "EU"):set(stored, { lsc = name })
    m:gauge("lumen_capacity_eu", "c", "EU"):set(v[2], { lsc = name })
    m:gauge("lumen_fill_ratio", "f"):set(stored / v[2], { lsc = name })
  end
  m:gauge("lumen_input_eut", "i", "EU/t"):set(math.floor(76540 * drift(now, 1, 0.05)), { lsc = "Main" })
  m:gauge("lumen_output_eut", "o", "EU/t"):set(67720, { lsc = "Main" })
  m:gauge("lumen_net_5m_eut", "n", "EU/t"):set(math.floor(2370 * drift(now, 3, 0.8)), { lsc = "Main" })
  m:gauge("lumen_net_1h_eut", "n", "EU/t"):set(7920, { lsc = "Main" })
  m:gauge("lumen_full_seconds", "f", "s"):set(37800, { lsc = "Main" })
  m:alert("low:Spare", "warn", "Spare low: 10%")
end }

-- Your own program: a tree farm.
local farm = R.agent{ node = "tree-farm", role = "farm", cycle = function(m, now)
  m:beginCycle()
  m:gauge("farm_logs_per_min", "l", "logs/min"):set(math.floor(212 * drift(now, 5, 0.2)))
  m:gauge("farm_saplings_ratio", "s"):set(0.64)
end }

local DOWN = function(node) return ('sum(prism_machine_state{node="%s", state="down"}) > 0'):format(node) end
local RUNNING = function(node) return ('sum(prism_machine_state{node="%s", state="running"}) > 0'):format(node) end
local CFG = [[return {
  sample = 5,
  panels = {
    { label = "Ore backlog", value = 'sum(prism_backlog_items{node="prism-ore"})', unit = "items", max = 25000,
      status = { { "bad", ']] .. DOWN("prism-ore") .. [[' }, { "good", ']] .. RUNNING("prism-ore") .. [[' } } },
    { label = "Ore machines", text = "{r}/{n} running",
      values = { r = 'sum(prism_machine_state{node="prism-ore", state="running"})',
                 n = 'count(prism_machine_state{node="prism-ore", state="running"})' },
      dots = 'prism_machine_state{node="prism-ore"}' },
    { label = "Washers", value = 'sum(prism_backlog_items{node="prism-ore", process="wash"})', unit = "items", max = 10000 },
    { label = "Centrifuges", value = 'sum(prism_backlog_items{node="prism-ore", process="centrifuge"})', unit = "items",
      max = 10000 },
    { label = "Smelting", value = 'sum(prism_backlog_items{node="prism-smelt"})', unit = "items",
      status = { { "bad", ']] .. DOWN("prism-smelt") .. [[' }, { "good", ']] .. RUNNING("prism-smelt") .. [[' } } },
    { label = "EBFs", text = "{r}/{n} running",
      values = { r = 'sum(prism_machine_state{node="prism-smelt", state="running"})',
                 n = 'count(prism_machine_state{node="prism-smelt", state="running"})' },
      dots = 'prism_machine_state{node="prism-smelt"}' },
    { label = "Gems", value = 'sum(prism_backlog_items{node="prism-gems"})', unit = "items",
      status = { { "good", ']] .. RUNNING("prism-gems") .. [[' } } },
    { label = "Scan", value = "max(prism_scan_seconds)", unit = "s", warnAbove = 2, badAbove = 5 },
    { label = "Power", value = "sum(lumen_stored_eu) / sum(lumen_capacity_eu)", format = "percent",
      status = { { "bad", "$value < 0.1" }, { "good", "sum(lumen_net_1h_eut) > 0" } } },
    { label = "Stored", text = "{s} / {c} EU", values = { s = "sum(lumen_stored_eu)", c = "sum(lumen_capacity_eu)" } },
    { label = "Flow", text = "{i} in {o} out EU/t", values = { i = "sum(lumen_input_eut)", o = "sum(lumen_output_eut)" } },
    { label = "Net 5m", value = "sum(lumen_net_5m_eut)", unit = "EU/t", format = "signed", color = "sign" },
    { label = "Full in", value = "min(lumen_full_seconds)", format = "duration", when = "count(lumen_full_seconds) > 0" },
    { label = "Spare", value = 'lumen_fill_ratio{lsc="Spare"}', format = "percent", warnBelow = 0.25, badBelow = 0.05 },
    { label = "Tree farm", value = "farm_logs_per_min", unit = "logs/min" },
    { label = "Saplings", value = "farm_saplings_ratio", format = "percent" },
  },
  hud = { blocks = { { anchor = "top-left", width = 190, dots = "left", elements = {   -- top-left: a tight picture
    { kind = "bar", label = "LSCs", value = "sum(lumen_stored_eu) / sum(lumen_capacity_eu)", format = "percent",
      warnBelow = 0.25, badBelow = 0.1 },
    { kind = "text", label = "Net", value = "sum(lumen_net_5m_eut)", unit = "EU/t", format = "signed", color = "sign" },
    { kind = "gap" },
    { kind = "bar", label = "Ore", value = 'sum(prism_backlog_items{node="prism-ore"})', max = 25000 },
    { kind = "text", label = "Ore line", dots = 'prism_machine_state{node="prism-ore"}' },
    { kind = "text", label = "EBF line", dots = 'prism_machine_state{node="prism-smelt"}' },
    { kind = "gap" },
    { kind = "alerts", count = 3 },
  } } } },
}]]

M.setTime(0)
M.resize(160, 50)
local G = glassesMock.new()
G.proxy.getBindPlayers = function() return "Aaron" end
local seen = {}
local ok, err = R.run{ cfg = CFG, agents = { ore, smelt, gems, power, farm }, keyboard = true, terminals = { ["gl-a"] = G },
  script = function(t)
    if t < 240 then return nil end                -- four minutes: 48 samples for each sparkline
    H.screen("showcase-dashboard")
    H.glasses("showcase-hud", G)
    seen.nodes = M.find("tree-farm", 3) and M.find("prism-smelt", 3) and M.find("prism-gems", 3) and M.find("power-room", 3)
    seen.alerts = M.find("EBF 3: no power", 3) and M.find("Centrifuge B idle", 3) and M.find("Spare low", 3)
    seen.panels = M.find("logs/min", 3) and M.find("3/4 running", 3) and M.find("9/10 running", 3)
    seen.hud = G.find("LSCs") and G.find("Ore line") and G.find("EBF 3: no power")
    local line = G.find("Ore line")
    seen.left = line and 0
    for _, s in ipairs(G.live()) do
      if line and s.visible and s.text == "●" and s.y == line.y then
        seen.left = (s.x < line.x) and seen.left and seen.left + 1 or false
      end
    end
    return "stop"
  end }
check(ok, "lens-hub runs the showcase" .. (ok and "" or (": " .. tostring(err))))
check(seen.nodes, "five agents on the dashboard, your own program among them")
check(seen.alerts, "the three alerts are listed")
check(seen.panels, "panels from every agent")
check(seen.hud, "the HUD block shows power, the ore line and the alerts")
check(seen.left == #ORE, 'dots = "left" in lens-hub.cfg: all ' .. #ORE .. " machine dots before the label (" .. tostring(seen.left) .. ")")
H.done()
