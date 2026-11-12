--[[ lens.hub.huds: one HUD per Glasses Terminal, each showing the settings of the player wearing glasses
  linked to it. A terminal shows the same widgets to everyone linked to it (OC Glasses has no per-player
  widgets), so per-player HUDs need a terminal each. Players' own settings live in /home/lens-hud.cfg, which
  only the hub writes (from the dashboard's HUD editor); lens-hub.cfg's hud is everyone's default.

  local hs = require("lens.hub.huds").new(terminals, defaults, path)
    terminals: { [address] = Glasses Terminal proxy }; defaults: cfg.hud (checked); path: players' settings
  hs:onGlasses(address, player, w, h)   a glasses_on: that terminal's wearer and GUI size
  hs:draw(model, evaluate, panels)      draw every terminal. evaluate(views) -> { { label, text, frac, level } }
  hs:catalog(panels) -> { view... }     what a player can pick: views in the default HUD, then panels with
                                        other labels (a label names a view)
  hs:settings(player) -> s              the player's settings, or a copy of the defaults:
    { own = bool, scale, blocks = { { anchor, x, y, width, elements = { element... } }... } }
    element: { kind = "bar" | "text", view = label } | { kind = "alerts", count } | { kind = "gap" }
  hs:change(player, fn)                 fn(s) edits the player's settings; saved at once -> true | false, err
  hs:reset(player)                      back to the defaults (removes their entry) -> true | false, err
  hs:wearing(player) -> n               terminals that player is wearing glasses on
  hs:clear()                            remove every widget
  hs.calls, hs.error                    component calls so far (all terminals); the latest draw failure, or nil
  huds.LIMITS                           { scale, width, count, blocks, elements } -> { min, max, step }

  A terminal's wearer comes from glasses_on, or at start from getBindPlayers when it names exactly one player.
  A terminal with no known wearer, or a wearer without settings, shows the defaults.
]]

local hud = require("lens.hub.hud")
local files = require("lens.files")
local config = require("lens.hub.config")

local huds = {}

huds.LIMITS = { scale = { 0.5, 3, 0.25 }, width = { 100, 400, 20 }, count = { 0, 8, 1 },
  blocks = { 1, 6 }, elements = { 0, 20 } }

local ANCHOR = {}
for _, a in ipairs(config.ANCHORS) do ANCHOR[a] = true end

-- Player names from getBindPlayers, whatever shape it returns: a name, a list of names, or a list of tables
-- with a name. (Assumed; docs/architecture.md.)
local function boundPlayers(proxy)
  local ok, v = pcall(proxy.getBindPlayers)
  if not ok then return {} end
  local out = {}
  local function add(x)
    if type(x) == "string" and x ~= "" then out[#out + 1] = x
    elseif type(x) == "table" and type(x.name) == "string" then out[#out + 1] = x.name end
  end
  if type(v) == "table" then for _, x in pairs(v) do add(x) end else add(v) end
  return out
end

local function within(v, lim) return type(v) == "number" and v >= lim[1] and v <= lim[2] end

-- Settings read from the file (or edited): only well-formed parts survive. The first editor's form
-- (anchor, bars = { labels }, width, alerts) becomes one block.
local function clean(s)
  if type(s) ~= "table" then return nil end
  local out = { scale = within(s.scale, huds.LIMITS.scale) and s.scale or nil, blocks = {} }
  local blocks = s.blocks
  if blocks == nil and (s.bars or s.anchor) then
    local anchor = ANCHOR[s.anchor] and s.anchor or "top-right"
    local elements = {}
    for _, b in ipairs(type(s.bars) == "table" and s.bars or {}) do elements[#elements + 1] = { kind = "bar", view = b } end
    elements[#elements + 1] = { kind = "alerts", count = within(s.alerts, huds.LIMITS.count) and s.alerts or 3 }
    blocks = { { anchor = anchor, width = s.width, elements = elements } }
  end
  if type(blocks) ~= "table" then return nil end
  for _, b in ipairs(blocks) do
    if type(b) == "table" and #out.blocks < huds.LIMITS.blocks[2] then
      local anchor = ANCHOR[b.anchor] and b.anchor or "top-right"
      local dx, dy = config.offset(anchor)
      local nb = { anchor = anchor, x = type(b.x) == "number" and b.x or dx, y = type(b.y) == "number" and b.y or dy,
        width = within(b.width, huds.LIMITS.width) and b.width or 160, elements = {} }
      for _, el in ipairs(type(b.elements) == "table" and b.elements or {}) do
        if type(el) == "table" and #nb.elements < huds.LIMITS.elements[2] then
          if (el.kind == "bar" or el.kind == "text") and type(el.view) == "string" then
            nb.elements[#nb.elements + 1] = { kind = el.kind, view = el.view }
          elseif el.kind == "alerts" then
            nb.elements[#nb.elements + 1] = { kind = "alerts", count = within(el.count, huds.LIMITS.count) and el.count or 3 }
          elseif el.kind == "gap" then
            nb.elements[#nb.elements + 1] = { kind = "gap" }
          end
        end
      end
      out.blocks[#out.blocks + 1] = nb
    end
  end
  if #out.blocks == 0 then return nil end
  return out
end

local function lit(v)
  if type(v) == "string" then return ("%q"):format(v) end
  return tostring(v)
end

local function serialize(players)
  local names = {}
  for name in pairs(players) do names[#names + 1] = name end
  table.sort(names)
  local lines = { "-- lens-hud.cfg: each player's own HUD, written by lens-hub's HUD editor (tap HUD on the dashboard).",
    "-- Players not listed get the hud in lens-hub.cfg.", "return {" }
  for _, name in ipairs(names) do
    local s = players[name]
    lines[#lines + 1] = ("  [%q] = { scale = %s, blocks = {"):format(name, lit(s.scale or 1))
    for _, b in ipairs(s.blocks) do
      local els = {}
      for _, el in ipairs(b.elements) do
        local parts = { "kind = " .. lit(el.kind) }
        if el.view then parts[#parts + 1] = "view = " .. lit(el.view) end
        if el.count then parts[#parts + 1] = "count = " .. lit(el.count) end
        els[#els + 1] = "{ " .. table.concat(parts, ", ") .. " }"
      end
      lines[#lines + 1] = ("    { anchor = %s, x = %s, y = %s, width = %s, elements = {"):format(lit(b.anchor), lit(b.x),
        lit(b.y), lit(b.width))
      for _, e in ipairs(els) do lines[#lines + 1] = "      " .. e .. "," end
      lines[#lines + 1] = "    } },"
    end
    lines[#lines + 1] = "  } },"
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

local Huds = {}
Huds.__index = Huds

function huds.new(terminals, defaults, path)
  local self = setmetatable({ defaults = defaults, path = path, terms = {}, players = {}, calls = 0 }, Huds)
  local addresses = {}
  for address in pairs(terminals) do addresses[#addresses + 1] = address end
  table.sort(addresses)
  for _, address in ipairs(addresses) do
    local proxy = terminals[address]
    local bound = boundPlayers(proxy)
    self.terms[#self.terms + 1] = { address = address, hud = hud.new(proxy, {}), player = #bound == 1 and bound[1] or nil }
  end
  local saved = path and files.loadTable(path)
  if type(saved) == "table" then
    for name, s in pairs(saved) do
      if type(name) == "string" then self.players[name] = clean(s) end
    end
  end
  return self
end

function Huds:onGlasses(address, player, w, h)
  for _, t in ipairs(self.terms) do
    if t.address == address then
      if type(player) == "string" and player ~= "" then t.player = player end
      if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then t.screen = { w = w, h = h } end
    end
  end
end

-- The defaults as settings: elements name their views by label.
function Huds:defaultSettings()
  local s = { own = false, scale = self.defaults.scale or 1, blocks = {} }
  for _, b in ipairs(self.defaults.blocks or {}) do
    local nb = { anchor = b.anchor, x = b.x, y = b.y, width = b.width, elements = {} }
    for _, el in ipairs(b.elements) do
      if el.kind == "bar" or el.kind == "text" then
        nb.elements[#nb.elements + 1] = { kind = el.kind, view = el.label }
      else
        nb.elements[#nb.elements + 1] = { kind = el.kind, count = el.count }
      end
    end
    s.blocks[#s.blocks + 1] = nb
  end
  if #s.blocks == 0 then
    local dx, dy = config.offset("top-right")
    s.blocks[1] = { anchor = "top-right", x = dx, y = dy, width = 160, elements = { { kind = "alerts", count = 3 } } }
  end
  return s
end

function Huds:settings(player)
  local own = player and self.players[player]
  if not own then return self:defaultSettings() end
  local s = clean(own)
  s.own, s.scale = true, s.scale or self.defaults.scale or 1
  return s
end

function Huds:catalog(panels)
  local out, seen = {}, {}
  for _, b in ipairs(self.defaults.blocks or {}) do
    for _, el in ipairs(b.elements) do
      if (el.kind == "bar" or el.kind == "text") and not seen[el.label] then out[#out + 1] = el; seen[el.label] = true end
    end
  end
  for _, p in ipairs(panels or {}) do
    if not seen[p.label] then out[#out + 1] = p; seen[p.label] = true end
  end
  return out
end

function Huds:save()
  if not self.path then return true end
  return files.writeAtomic(self.path, serialize(self.players))
end

function Huds:change(player, fn)
  local s = self:settings(player)
  fn(s)
  self.players[player] = clean(s)
  return self:save()
end

function Huds:reset(player)
  self.players[player] = nil
  return self:save()
end

function Huds:wearing(player)
  local n = 0
  for _, t in ipairs(self.terms) do if t.player == player then n = n + 1 end end
  return n
end

-- A player's blocks, ready to draw: each element's view evaluated (elements whose view is gone are skipped).
function Huds:blocksFor(player, byLabel, evaluate)
  local s = self:settings(player)
  local views, slots = {}, {}
  local blocks = {}
  for i, b in ipairs(s.blocks) do
    local items = {}
    for _, el in ipairs(b.elements) do
      if el.kind == "bar" or el.kind == "text" then
        local view = byLabel[el.view]
        if view then
          local item = { kind = el.kind }
          items[#items + 1] = item
          views[#views + 1] = view
          slots[#slots + 1] = item
        end
      else
        items[#items + 1] = { kind = el.kind, count = el.count }
      end
    end
    blocks[i] = { anchor = b.anchor, x = b.x, y = b.y, width = b.width, items = items }
  end
  for i, v in ipairs(evaluate(views)) do
    local item = slots[i]
    item.label, item.text, item.frac, item.level = v.label, v.text, v.frac, v.level
  end
  return blocks, s.scale
end

function Huds:draw(m, evaluate, panels)
  local byLabel = {}
  for _, v in ipairs(self:catalog(panels)) do byLabel[v.label] = v end
  local errs, calls = {}, 0
  for _, t in ipairs(self.terms) do
    local blocks, scale = self:blocksFor(t.player, byLabel, evaluate)
    t.hud.opts = { scale = scale, alpha = self.defaults.alpha, colors = self.defaults.colors }
    local view = setmetatable({ hudBlocks = blocks, screen = t.screen }, { __index = m })
    local ok, err = pcall(t.hud.draw, t.hud, view)
    if not ok then errs[#errs + 1] = tostring(err) end
    calls = calls + t.hud.calls
  end
  self.calls = calls
  self.error = errs[1]
end

function Huds:clear()
  for _, t in ipairs(self.terms) do pcall(t.hud.clear, t.hud) end
end

return huds
