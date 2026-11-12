--[[ lens.hub.config: /home/lens-hub.cfg, its defaults and checks. Every option: docs/hub.md.

  DEFAULTS                     every setting and its default
  load(path) -> cfg | nil, err   The file is optional: without one, every default applies (cfg.missing = true).
                               err is readable ("panel 2 (Ore): expected ) at 14"). cfg.nonCritical becomes a set.
  check(cfg) -> cfg | nil, err   the same checks on a table (load uses it)

  A panel: { label, value = query, of = query?, max = number?, unit = string?, percent = bool?,
             warnAbove?, badAbove?, warnBelow?, badBelow? }
  hud: the AR glasses HUD (HUD_DEFAULTS fill what's missing); hud = false turns it off.
       hud.bars: bars in the same form as panels (label, value, max/of/percent, thresholds)
]]

local query = require("lens.hub.query")
local rules = require("lens.hub.rules")

local config = {}

config.DEFAULTS = {
  node = "hub", port = 4243, token = nil, staleAfter = 3, beep = true, sample = 10,
  nonCritical = {}, panels = {}, rules = {}, hud = {},
}

config.HUD_DEFAULTS = {
  x = 4, y = 20, width = 160, scale = 1, alerts = 3, alpha = 0.35, colors = "float", bars = {},
}

local THRESHOLDS = { "warnAbove", "badAbove", "warnBelow", "badBelow" }

local function checkPanel(i, p)
  local where = "panel " .. i
  if type(p) ~= "table" then return where .. ": must be a table" end
  if type(p.label) ~= "string" or p.label == "" then return where .. ": needs a label" end
  where = ("panel %d (%s)"):format(i, p.label)
  for _, k in ipairs({ "value", "of" }) do
    if p[k] ~= nil or k == "value" then
      local q, err = query.compile(p[k])
      if not q then return where .. ": " .. k .. ": " .. tostring(err) end
    end
  end
  if p.max ~= nil and (type(p.max) ~= "number" or p.max <= 0) then return where .. ": max must be a number above 0" end
  if p.max ~= nil and p.of ~= nil then return where .. ": use max or of, not both" end
  if p.unit ~= nil and type(p.unit) ~= "string" then return where .. ": unit must be text" end
  for _, k in ipairs(THRESHOLDS) do
    if p[k] ~= nil and type(p[k]) ~= "number" then return where .. ": " .. k .. " must be a number" end
  end
end

function config.check(c)
  if type(c) ~= "table" then return nil, "the config must return a table" end
  for k, v in pairs(config.DEFAULTS) do
    if c[k] == nil then
      if type(v) == "table" then c[k] = {} else c[k] = v end
    end
  end
  if type(c.node) ~= "string" or c.node == "" then return nil, "node must be a name" end
  if math.type(c.port) ~= "integer" or c.port < 1 or c.port > 65535 then return nil, "port must be 1-65535" end
  if c.token ~= nil and type(c.token) ~= "string" then return nil, "token must be text or nil" end
  for _, k in ipairs({ "staleAfter", "sample" }) do
    if type(c[k]) ~= "number" or c[k] <= 0 then return nil, k .. " must be a number above 0" end
  end
  if type(c.nonCritical) ~= "table" then return nil, "nonCritical must be a list of node names" end
  local set = {}
  for k, v in pairs(c.nonCritical) do
    if type(k) == "number" then set[v] = true else set[k] = v and true or nil end
  end
  c.nonCritical = set
  if type(c.panels) ~= "table" then return nil, "panels must be a list" end
  for i, p in ipairs(c.panels) do
    local err = checkPanel(i, p)
    if err then return nil, err end
  end
  local _, err = rules.new(c.rules)
  if err then return nil, err end
  if c.hud ~= false then
    if type(c.hud) ~= "table" then return nil, "hud must be a table, or false for none" end
    for k, v in pairs(config.HUD_DEFAULTS) do if c.hud[k] == nil then c.hud[k] = v end end
    local h = c.hud
    if h.colors ~= "float" and h.colors ~= "byte" then return nil, 'hud.colors must be "float" or "byte"' end
    for _, k in ipairs({ "x", "y", "alerts" }) do
      if type(h[k]) ~= "number" or h[k] < 0 then return nil, "hud." .. k .. " must be a number" end
    end
    for _, k in ipairs({ "width", "scale" }) do
      if type(h[k]) ~= "number" or h[k] <= 0 then return nil, "hud." .. k .. " must be a number above 0" end
    end
    if type(h.alpha) ~= "number" or h.alpha < 0 or h.alpha > 1 then return nil, "hud.alpha must be 0..1" end
    if type(h.bars) ~= "table" then return nil, "hud.bars must be a list of bars" end
    for i, b in ipairs(h.bars) do
      local e = checkPanel(i, b)
      if e then return nil, "hud." .. e:gsub("^panel", "bar") end
    end
  end
  return c
end

function config.load(path)
  local f = io.open(path, "r")
  if not f then
    local c = config.check({})
    c.missing = true
    return c
  end
  local text = f:read("*a")
  f:close()
  local chunk, err = load(text, "=" .. path, "t", {})
  if not chunk then return nil, err end
  local ok, c = pcall(chunk)
  if not ok then return nil, tostring(c) end
  return config.check(c)
end

return config
