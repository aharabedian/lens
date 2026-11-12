--[[ lens.hub.huds: one HUD per Glasses Terminal, each showing the settings of the player wearing glasses
  linked to it. A terminal shows the same widgets to everyone linked to it (OC Glasses has no per-player
  widgets), so per-player HUDs need a terminal each. Players' own settings are kept by the board
  (lens.hub.board, /home/lens-board.cfg), changed from the dashboard's HUD editor; lens-hub.cfg's hud is
  everyone's default.

  local hs = require("lens.hub.huds").new(terminals, defaults, store)
    terminals: { [address] = Glasses Terminal proxy }; defaults: cfg.hud (checked)
    store: where players' settings live: { players() -> table, setPlayers(table) -> true | nil, err }, which
    lens.hub.board is; nil keeps them in memory
  hs:onGlasses(address, player, w, h)   a glasses_on: that terminal's wearer and GUI size
  hs:draw(model, evaluate, views)       draw every terminal. evaluate(views) -> { { label, text, frac, level, dots?,
                                        hidden? } } (lens.hub.app's evaluate); hidden elements aren't drawn
  hs:catalog(views) -> { view... }      what a player can pick: `views` (the board's library), then views in
                                        the default HUD with other labels (a label names a view)
  hs:settings(player) -> s              the player's active preset, or a copy of the defaults:
    { own = bool, preset = name, scale, blocks = { { anchor, x, y, width, elements = { element... } }... } }
    element: { kind = "bar" | "text", view = label } | { kind = "alerts", count } | { kind = "gap" }
  hs:change(player, fn)                 fn(s) edits the active preset; saved at once -> true | nil, err
  hs:reset(player)                      the active preset back to the defaults -> true | nil, err

  Presets: each player has named HUDs (at least "main") and shows the active one. A preset without settings of
  its own follows lens-hub.cfg's hud.
  hs:presets(player) -> { name... }, active
  hs:usePreset(player, name) -> true | nil, err
  hs:addPreset(player) -> name | nil, err        a copy of the active one ("HUD 2", ...), made active
  hs:renamePreset(player, old, new) -> true | nil, err
  hs:deletePreset(player, name) -> true | nil, err   not the last one; the first left becomes active if it was
  huds.MAX_PRESETS, huds.NAME_LENGTH
  hs:wearing(player) -> n               terminals that player is wearing glasses on
  hs:clear()                            remove every widget
  hs.calls, hs.error                    component calls so far (all terminals); the latest draw failure, or nil
  huds.LIMITS                           { scale, width, count, blocks, elements } -> { min, max, step }

  A terminal's wearer comes from glasses_on, or at start from getBindPlayers when it names exactly one player.
  A terminal with no known wearer, or a wearer without settings, shows the defaults.
]]

local hud = require("lens.hub.hud")
local config = require("lens.hub.config")

local huds = {}

huds.LIMITS = { scale = { 0.5, 3, 0.25 }, width = { 100, 400, 20 }, count = { 0, 8, 1 },
  blocks = { 1, 6 }, elements = { 0, 20 } }
huds.MAX_PRESETS = 8
huds.NAME_LENGTH = 16

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

-- A player's record: { active = name, presets = { { name, scale?, blocks? }... } }. An older record (one HUD:
-- scale and blocks, or the first editor's form) becomes one preset, "main". A preset without blocks follows
-- the defaults.
local function cleanRecord(r)
  if type(r) ~= "table" then return nil end
  local out = { presets = {} }
  if type(r.presets) == "table" then
    local seen = {}
    for _, p in ipairs(r.presets) do
      if type(p) == "table" and type(p.name) == "string" and p.name ~= "" and not seen[p.name]
        and #out.presets < huds.MAX_PRESETS then
        seen[p.name] = true
        local c = (p.blocks or p.bars or p.anchor) and clean(p) or nil
        out.presets[#out.presets + 1] = { name = p.name, settings = c }
      end
    end
    out.active = (type(r.active) == "string" and seen[r.active]) and r.active or nil
  else
    local c = clean(r)
    if c then out.presets[1] = { name = "main", settings = c } end
  end
  if #out.presets == 0 then return nil end
  out.active = out.active or out.presets[1].name
  return out
end

-- The record as it's stored: presets as plain tables (settings inline).
local function storeRecord(r)
  local out = { active = r.active, presets = {} }
  for _, p in ipairs(r.presets) do
    local e = { name = p.name }
    if p.settings then e.scale, e.blocks = p.settings.scale, p.settings.blocks end
    out.presets[#out.presets + 1] = e
  end
  return out
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local Huds = {}
Huds.__index = Huds

function huds.new(terminals, defaults, store)
  local self = setmetatable({ defaults = defaults, store = store, terms = {}, players = {}, calls = 0 }, Huds)
  local addresses = {}
  for address in pairs(terminals) do addresses[#addresses + 1] = address end
  table.sort(addresses)
  for _, address in ipairs(addresses) do
    local proxy = terminals[address]
    local bound = boundPlayers(proxy)
    self.terms[#self.terms + 1] = { address = address, hud = hud.new(proxy, {}), player = #bound == 1 and bound[1] or nil }
  end
  local saved = store and store:players()
  if type(saved) == "table" then
    for name, s in pairs(saved) do
      if type(name) == "string" then self.players[name] = cleanRecord(s) end
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

-- The player's record, made when needed (one preset, "main", following the defaults).
function Huds:record(player, make)
  local r = self.players[player]
  if not r and make then
    r = { active = "main", presets = { { name = "main" } } }
    self.players[player] = r
  end
  return r
end

local function find(r, name)
  for i, p in ipairs(r.presets) do if p.name == name then return p, i end end
end

function Huds:settings(player)
  local r = player and self:record(player)
  local p = r and find(r, r.active)
  local s
  if p and p.settings then
    s = clean(p.settings)
    s.own, s.scale = true, s.scale or self.defaults.scale or 1
  else
    s = self:defaultSettings()
  end
  s.preset = p and p.name or "main"
  return s
end

function Huds:presets(player)
  local r = self:record(player)
  if not r then return { "main" }, "main" end
  local names = {}
  for _, p in ipairs(r.presets) do names[#names + 1] = p.name end
  return names, r.active
end

function Huds:usePreset(player, name)
  local r = self:record(player, true)
  if not find(r, name) then return nil, "no HUD called " .. tostring(name) end
  r.active = name
  return self:save()
end

function Huds:addPreset(player)
  local r = self:record(player, true)
  if #r.presets >= huds.MAX_PRESETS then return nil, ("at most %d HUDs"):format(huds.MAX_PRESETS) end
  local n = #r.presets + 1
  while find(r, "HUD " .. n) do n = n + 1 end
  local name = "HUD " .. n
  local current = find(r, r.active)
  r.presets[#r.presets + 1] = { name = name, settings = current and copy(current.settings) }
  r.active = name
  local ok, err = self:save()
  if not ok then return nil, err end
  return name
end

function Huds:renamePreset(player, old, new)
  local r = self:record(player, true)
  local p = find(r, old)
  if not p then return nil, "no HUD called " .. tostring(old) end
  new = type(new) == "string" and new:match("^%s*(.-)%s*$") or ""
  if new == "" then return nil, "a HUD needs a name" end
  if #new > huds.NAME_LENGTH then return nil, ("names are at most %d characters"):format(huds.NAME_LENGTH) end
  if new ~= old and find(r, new) then return nil, "there's already a HUD called " .. new end
  p.name = new
  if r.active == old then r.active = new end
  return self:save()
end

function Huds:deletePreset(player, name)
  local r = self:record(player, true)
  local _, i = find(r, name)
  if not i then return nil, "no HUD called " .. tostring(name) end
  if #r.presets == 1 then return nil, "the last HUD stays" end
  table.remove(r.presets, i)
  if r.active == name then r.active = r.presets[1].name end
  return self:save()
end

function Huds:catalog(views)
  local out, seen = {}, {}
  for _, v in ipairs(views or {}) do
    if not seen[v.label] then out[#out + 1] = v; seen[v.label] = true end
  end
  for _, b in ipairs(self.defaults.blocks or {}) do
    for _, el in ipairs(b.elements) do
      if (el.kind == "bar" or el.kind == "text") and not seen[el.label] then out[#out + 1] = el; seen[el.label] = true end
    end
  end
  return out
end

function Huds:save()
  if not self.store then return true end
  local out = {}
  for name, r in pairs(self.players) do out[name] = storeRecord(r) end
  return self.store:setPlayers(out)
end

function Huds:change(player, fn)
  local s = self:settings(player)
  fn(s)
  local r = self:record(player, true)
  find(r, r.active).settings = clean(s)
  return self:save()
end

function Huds:reset(player)
  local r = self:record(player, true)
  find(r, r.active).settings = nil
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
    item.label, item.text, item.frac, item.level, item.dots, item.hidden = v.label, v.text, v.frac, v.level, v.dots, v.hidden
  end
  for _, b in ipairs(blocks) do                 -- elements whose view's `when` is false now drop out
    local keep = {}
    for _, item in ipairs(b.items) do if not item.hidden then keep[#keep + 1] = item end end
    b.items = keep
  end
  return blocks, s.scale
end

function Huds:draw(m, evaluate, views)
  local byLabel = {}
  for _, v in ipairs(self:catalog(views)) do byLabel[v.label] = v end
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
