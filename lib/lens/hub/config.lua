--[[ lens.hub.config: /home/lens-hub.cfg, its defaults and checks. Every option: docs/hub.md.

  DEFAULTS                     every setting and its default
  load(path) -> cfg | nil, err   The file is optional: without one, every default applies (cfg.missing = true).
                               err is readable ("panel 2 (Ore): expected ) at 14"). cfg.nonCritical becomes a set.
  check(cfg) -> cfg | nil, err   the same checks on a table (load uses it)

  A panel (a view, lens.hub.format): { label, value = query, of = query?, max = number?, unit = string?,
             format = "auto" | "percent" | "duration" | "signed", color = "thresholds" | "sign" | "none",
             warnAbove?, badAbove?, warnBelow?, badBelow? }   (percent = true is the same as format = "percent")
  resolution: "fit" (fill the screen's shape), "max" (the GPU's largest) or { width, height }
  hud: the AR glasses HUD (HUD_DEFAULTS fill what's missing); hud = false turns it off. After check, hud.blocks
       is always there: { { anchor, x, y, width, elements = { element... } }... } where an element is a view
       with kind = "bar" | "text", or { kind = "alerts", count }, or { kind = "gap" }. x, y: GUI pixels from the
       anchor point, right and down positive (default 4 in from the edges).
       Written without blocks (anchor, x, y as margins, width, alerts, bars), it becomes one block: the bars,
       then the alerts.
  ANCHORS: the nine anchor names; config.offset(anchor) -> the default x, y for it
  checkView(view) -> err | nil   one view, as a panel is checked
  editors: nil (anyone may edit the dashboard on the screen) or a list of player names
]]

local query = require("lens.hub.query")
local rules = require("lens.hub.rules")

local config = {}

config.DEFAULTS = {
  node = "hub", port = 4243, token = nil, staleAfter = 3, beep = true, sample = 10, resolution = "fit", editors = nil,
  nonCritical = {}, panels = {}, rules = {}, hud = {},
}

config.ANCHORS = { "top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right" }
local ANCHOR = {}
for _, a in ipairs(config.ANCHORS) do ANCHOR[a] = true end

-- The default offset for an anchor: 4 GUI pixels in from the edges it touches.
function config.offset(anchor)
  local x = anchor:find("left", 1, true) and 4 or anchor:find("right", 1, true) and -4 or 0
  local y = anchor:find("^top") and 4 or anchor:find("^bottom") and -4 or 0
  return x, y
end

config.HUD_DEFAULTS = {
  anchor = "top-right", x = 4, y = 4, width = 160, scale = 1, alerts = 3, alpha = 0.35, colors = "float", bars = {},
}

local THRESHOLDS = { "warnAbove", "badAbove", "warnBelow", "badBelow" }

local FORMAT, COLOR = {}, {}
for _, f in ipairs(require("lens.hub.format").FORMATS) do FORMAT[f] = true end
for _, f in ipairs(require("lens.hub.format").COLORS) do COLOR[f] = true end

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
  if p.percent and p.format == nil then p.format = "percent" end
  if p.format ~= nil and not FORMAT[p.format] then
    return where .. ': format must be "auto", "percent", "duration" or "signed"'
  end
  if p.color ~= nil and not COLOR[p.color] then return where .. ': color must be "thresholds", "sign" or "none"' end
end

-- A view (a panel, or a HUD bar or text) on its own -> err | nil. Fills format from percent, like check.
function config.checkView(v)
  local e = checkPanel(0, v)
  return e and (e:gsub("^panel 0[^:]*: ", "")) or nil
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
    for _, k in ipairs({ "width", "scale" }) do
      if type(h[k]) ~= "number" or h[k] <= 0 then return nil, "hud." .. k .. " must be a number above 0" end
    end
    if type(h.alpha) ~= "number" or h.alpha < 0 or h.alpha > 1 then return nil, "hud.alpha must be 0..1" end
    local e = h.blocks == nil and config.legacyBlocks(h) or nil
    if e then return nil, e end
    e = config.checkBlocks(h.blocks, h)
    if e then return nil, e end
  end
  if c.editors ~= nil then
    if type(c.editors) ~= "table" then return nil, 'editors must be a list of player names: { "Steve" }' end
    for _, n in ipairs(c.editors) do
      if type(n) ~= "string" then return nil, 'editors must be a list of player names: { "Steve" }' end
    end
  end
  local r = c.resolution
  if r ~= "fit" and r ~= "max" and not (type(r) == "table" and math.type(r[1]) == "integer"
    and math.type(r[2]) == "integer" and r[1] >= 40 and r[2] >= 12) then
    return nil, 'resolution must be "fit", "max" or { width, height } (at least { 40, 12 })'
  end
  return c
end

-- hud written the first way (one corner, margins, bars, then alerts): one block. Sets h.blocks or -> err.
function config.legacyBlocks(h)
  if not ANCHOR[h.anchor] or h.anchor == "top" or h.anchor == "bottom" or h.anchor == "left" or h.anchor == "right"
    or h.anchor == "center" then
    return 'hud.anchor must be "top-right", "top-left", "bottom-right" or "bottom-left"'
  end
  for _, k in ipairs({ "x", "y", "alerts" }) do
    if type(h[k]) ~= "number" or h[k] < 0 then return "hud." .. k .. " must be a number" end
  end
  if type(h.bars) ~= "table" then return "hud.bars must be a list of bars" end
  for i, b in ipairs(h.bars) do
    local e = checkPanel(i, b)
    if e then return "hud." .. e:gsub("^panel", "bar") end
  end
  local elements = {}
  for _, b in ipairs(h.bars) do
    local el = {}
    for k, v in pairs(b) do el[k] = v end
    el.kind = "bar"
    elements[#elements + 1] = el
  end
  elements[#elements + 1] = { kind = "alerts", count = h.alerts }
  h.blocks = { {
    anchor = h.anchor, width = h.width, elements = elements,
    x = h.anchor:find("right", 1, true) and -h.x or h.x,
    y = h.anchor:find("^bottom") and -h.y or h.y,
  } }
end

local KINDS = { bar = true, text = true, alerts = true, gap = true }

-- Checks blocks (filling in each block's defaults from h) -> err | nil.
function config.checkBlocks(blocks, h)
  if type(blocks) ~= "table" then return "hud.blocks must be a list of blocks" end
  for i, b in ipairs(blocks) do
    local where = "hud block " .. i
    if type(b) ~= "table" then return where .. " must be a table" end
    b.anchor = b.anchor or "top-right"
    if not ANCHOR[b.anchor] then return where .. ": anchor must be one of " .. table.concat(config.ANCHORS, ", ") end
    local dx, dy = config.offset(b.anchor)
    b.x, b.y = b.x or dx, b.y or dy
    b.width = b.width or (h and h.width) or 160
    if type(b.x) ~= "number" or type(b.y) ~= "number" then return where .. ": x and y must be numbers" end
    if type(b.width) ~= "number" or b.width <= 0 then return where .. ": width must be a number above 0" end
    b.elements = b.elements or {}
    if type(b.elements) ~= "table" then return where .. ": elements must be a list" end
    for j, el in ipairs(b.elements) do
      local w = ("%s element %d"):format(where, j)
      if type(el) ~= "table" or not KINDS[el.kind] then return w .. ': kind must be "bar", "text", "alerts" or "gap"' end
      if el.kind == "bar" or el.kind == "text" then
        local e = checkPanel(j, el)
        if e then return where .. " " .. e:gsub("^panel", "element") end
      elseif el.kind == "alerts" then
        el.count = el.count or 3
        if type(el.count) ~= "number" or el.count < 0 then return w .. ": count must be a number" end
      end
    end
  end
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
