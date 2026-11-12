--[[ lens.setup.hub: lens-setup's steps -> /home/lens-hub.cfg (and /home/.shrc).

  run(env)   env = { cfgPath, shrcPath, modem?, glasses = bool, listen = seconds to wait for agents (5) }
    1. Hub: name, port (not PRISM's 4242), secret
    2. Agents and panels: says hello and lists the agents that answer; offers each PRISM router's standard
       panels (backlog, machines running, machines down), skipping panels already there
    3. AR glasses HUD (when a Glasses Terminal is attached): the corner, and a bar per PRISM router
    4. Start on boot: a lens-hub line in .shrc (other lines are kept)
    Then shows the file and saves it after a yes, keeping the old one as .bak. Settings, panels, bars and
    rules it doesn't ask about are kept. Raises input.CANCEL on Ctrl+D (nothing saved).
  panelsFor(node, hasMachines) -> panels      the standard panels for a PRISM router
  discover(modem, port, token, seconds) -> { { node, role, machines } }   who answers a hello
]]

local computer = require("computer")
local event    = require("event")
local codec    = require("lens.codec")
local config   = require("lens.hub.config")
local files    = require("lens.files")
local input    = require("lens.setup.input")
local render   = require("lens.setup.render")

local S = {}

local PRISM_CONTROL_PORT = 4242
local CORNERS = { "top-right", "top-left", "bottom-right", "bottom-left" }

local function short(node) return (node:gsub("^prism%-", "")) end

function S.panelsFor(node, hasMachines)
  local sel = ('node="%s"'):format(node)
  local out = {
    { label = short(node) .. " backlog", value = ("sum(prism_backlog_items{%s})"):format(sel), unit = "items" },
  }
  if hasMachines then
    out[#out + 1] = { label = short(node) .. " machines", value = ('sum(prism_machine_state{%s, state="running"})'):format(sel),
      of = ('count(prism_machine_state{%s, state="running"})'):format(sel) }
    out[#out + 1] = { label = short(node) .. " down", value = ('sum(prism_machine_state{%s, state="down"})'):format(sel),
      warnAbove = 1, badAbove = 3 }
  end
  return out
end

function S.discover(modem, port, token, seconds)
  local opened = modem.open(port)
  local enc = codec.encoder{ node = "lens-setup", role = "hub", boot = codec.newBoot(), token = token }
  modem.broadcast(port, enc:hello()[1])
  local asm, found, order = codec.assembler(), {}, {}
  local stop = computer.uptime() + seconds
  while computer.uptime() < stop do
    local ev = table.pack(event.pull(stop - computer.uptime(), "modem_message"))
    if ev[1] == "modem_message" and ev[4] == port then
      local msg = codec.decode(ev[6], token)
      local whole = msg and msg.kind ~= "hello" and asm:add(msg, computer.uptime())
      if whole then
        local n = found[whole.node]
        if not n then
          n = { node = whole.node, role = whole.role }
          found[whole.node] = n
          order[#order + 1] = n
        end
        if whole.kind == "describe" and (whole.metrics or {}).prism_machine_state then n.machines = true end
        for _, s in ipairs(whole.samples or {}) do
          if s[1] == "prism_machine_state" then n.machines = true end
        end
      end
    end
  end
  if opened then modem.close(port) end
  table.sort(order, function(a, b) return a.node < b.node end)
  return order
end

local function hubStep(c)
  input.header("Hub")
  c.node = input.ask("  this hub's name", c.node or "hub")
  while true do
    local port = input.number("  LENS port (every agent's lensPort)", c.port or codec.DEFAULT_PORT, 1, 65535)
    if port ~= PRISM_CONTROL_PORT then c.port = port; break end
    print("  4242 is PRISM's control-screen port - LENS needs its own (4243 is the usual)")
  end
  local token = input.ask("  shared secret (agents' lensToken; - for none)", type(c.token) == "string" and c.token or nil)
  if token == "-" then token = nil end
  c.token = token
end

local function agentsStep(c, env, found)
  input.header("Agents and panels")
  if not env.modem then
    print("  no network card: can't look for agents. Add panels by hand (docs/hub.md) or run lens-setup again.")
    return
  end
  print(("  saying hello on port %d and listening for %d s..."):format(c.port, env.listen or 5))
  for _, n in ipairs(S.discover(env.modem, c.port, c.token, env.listen or 5)) do found[#found + 1] = n end
  if #found == 0 then
    print("  no agents answered. On each PRISM router, set lensPort = " .. c.port
      .. (c.token and " and lensToken" or "") .. " (prism-setup asks), start prism, then run lens-setup again.")
    return
  end
  for _, n in ipairs(found) do print(("  found %s (%s)"):format(n.node, n.role or "?")) end
  c.panels = c.panels or {}
  local have = {}
  for _, p in ipairs(c.panels) do have[p.label] = true end
  for _, n in ipairs(found) do
    if n.role == "prism" then
      local new = {}
      for _, p in ipairs(S.panelsFor(n.node, n.machines)) do if not have[p.label] then new[#new + 1] = p end end
      if #new > 0 then
        local names = {}
        for _, p in ipairs(new) do names[#names + 1] = p.label end
        if input.yes(("  add panels for %s (%s)?"):format(n.node, table.concat(names, ", ")), true) then
          for _, p in ipairs(new) do c.panels[#c.panels + 1] = p; have[p.label] = true end
        end
      end
    else
      print(("  (no standard panels for %s agents yet: add them by hand)"):format(n.role or "?"))
    end
  end
end

local function hudStep(c, env, found)
  input.header("AR glasses HUD")
  if not env.glasses then
    print("  no Glasses Terminal attached: skipped" .. (c.hud == false and "" or " (hud settings are kept)"))
    return
  end
  if not input.yes("  show a HUD in glasses linked to this terminal?", c.hud ~= false) then c.hud = false; return end
  if c.hud == false or c.hud == nil then c.hud = {} end
  local h = c.hud
  if h.blocks then
    print("  hud uses blocks: change it in lens-hub.cfg, or each player on the dashboard (tap HUD)")
    return
  end
  local current = 1
  for i, corner in ipairs(CORNERS) do if corner == (h.anchor or "top-right") then current = i end end
  h.anchor = CORNERS[input.choose({ "top right", "top left", "bottom right", "bottom left" }, current)]
  h.bars = h.bars or {}
  local have = {}
  for _, b in ipairs(h.bars) do have[b.label] = true end
  for _, n in ipairs(found) do
    local label = short(n.node)
    if n.role == "prism" and not have[label] then
      local choices = { "backlog (a bar against a size you pick)", "none" }
      if n.machines then table.insert(choices, 1, "machines running (a bar of running / all)") end
      local pick = choices[input.choose(choices, 1)]
      local sel = ('node="%s"'):format(n.node)
      if pick:find("^machines") then
        h.bars[#h.bars + 1] = { label = label, value = ('sum(prism_machine_state{%s, state="running"})'):format(sel),
          of = ('count(prism_machine_state{%s, state="running"})'):format(sel) }
      elseif pick:find("^backlog") then
        local full = input.number("  backlog that counts as a full bar", 10000, 1, 2 ^ 53)
        h.bars[#h.bars + 1] = { label = label, value = ("sum(prism_backlog_items{%s})"):format(sel), max = full,
          warnAbove = math.floor(full * 0.6), badAbove = math.floor(full * 0.9) }
      end
    end
  end
end

-- .shrc with the lens-hub line added or removed; other lines are kept. nil when nothing changes.
local function shrcText(path, want)
  local text = files.read(path) or ""
  local out, present = {}, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local word = line:match("^%s*(%S+)")
    local prog = word and word:gsub("^.*/", ""):gsub("%.lua$", "")
    if prog == "lens-hub" then present = true else out[#out + 1] = line end
  end
  if out[#out] == "" then out[#out] = nil end
  if want == present then return nil end
  if want then out[#out + 1] = "lens-hub" end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

function S.run(env)
  local old, err = files.loadTable(env.cfgPath)
  if err then error(env.cfgPath .. " can't be read (" .. err .. "): fix or delete it first", 0) end
  local c = old or {}
  input.begin(4)
  hubStep(c)
  local found = {}
  agentsStep(c, env, found)
  hudStep(c, env, found)

  input.header("Start on boot")
  local shrc = shrcText(env.shrcPath, input.yes("  start lens-hub when this computer boots?", true))

  -- Write every setting with its value, defaults included, so the file shows what's in effect.
  for k, v in pairs(config.DEFAULTS) do
    if c[k] == nil and k ~= "token" then c[k] = type(v) == "table" and {} or v end
  end
  if type(c.hud) == "table" then
    for k, v in pairs(config.HUD_DEFAULTS) do
      if c.hud[k] == nil then c.hud[k] = type(v) == "table" and {} or v end
    end
  end

  local text = render.hub(c)
  -- What's saved must load: a mistake here is a bug in lens-setup, not something to write.
  local chunk = load(text, "=lens-hub.cfg", "t", {})
  local ran, saved = pcall(chunk or error)
  local okCheck, why = config.check(ran and saved or nil)
  if not okCheck then error("lens-setup made a config that doesn't load (" .. tostring(why) .. ") - please report it", 0) end

  print("")
  print("This will be saved to " .. env.cfgPath .. ":")
  io.write(text)
  if shrc then print(""); print("and " .. env.shrcPath .. " will be:"); io.write(shrc ~= "" and shrc or "(empty)\n") end
  if not input.yes("Save?", true) then print("nothing saved"); return false end
  local ok, saveErr = files.saveWithBackup(env.cfgPath, text)
  if not ok then error("can't write " .. env.cfgPath .. ": " .. tostring(saveErr), 0) end
  if shrc then
    ok, saveErr = files.writeAtomic(env.shrcPath, shrc)
    if not ok then error("can't write " .. env.shrcPath .. ": " .. tostring(saveErr), 0) end
  end
  print(("saved %d panel(s)%s. Start lens-hub (or restart it) to use it."):format(#(c.panels or {}),
    c.hud and c.hud.bars and #c.hud.bars > 0 and (" and " .. #c.hud.bars .. " HUD bar(s)") or ""))
  return true
end

return S
