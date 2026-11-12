--[[ lens.hub.huds: one HUD per Glasses Terminal, each showing the settings of the player wearing glasses
  linked to it. A terminal shows the same widgets to everyone linked to it (OC Glasses has no per-player
  widgets), so per-player HUDs need a terminal each. Players' own settings live in /home/lens-hud.cfg, which
  only the hub writes (from the dashboard's HUD editor); lens-hub.cfg's hud is everyone's default.

  local hs = require("lens.hub.huds").new(terminals, defaults, path)
    terminals: { [address] = Glasses Terminal proxy }; defaults: cfg.hud; path: the players' settings file
  hs:onGlasses(address, player, w, h)   a glasses_on: that terminal's wearer and GUI size
  hs:draw(model, evaluate)              draw every terminal. evaluate(bars) -> evaluated bars (App:evaluate)
  hs:catalog(panels) -> { bar... }      what a player can pick: hud.bars, then panels with other labels
  hs:settings(player) -> s              the player's settings, defaults filled in:
                                        { anchor, scale, width, alerts, bars = { label... }, own = bool }
  hs:change(player, fn)                 fn(s) edits the player's settings; saved at once -> true | false, err
  hs:reset(player)                      back to the defaults (removes their entry) -> true | false, err
  hs:wearing(player) -> n               terminals that player is wearing glasses on
  hs:clear()                            remove every widget
  hs.calls, hs.error                    component calls so far (all terminals); the latest draw failure, or nil

  A terminal's wearer comes from glasses_on, or at start from getBindPlayers when it names exactly one player.
  A terminal with no known wearer, or a wearer without settings, shows the defaults.
]]

local hud = require("lens.hub.hud")
local files = require("lens.files")

local huds = {}

huds.ANCHORS = { "top-left", "top-right", "bottom-left", "bottom-right" }
huds.LIMITS = { scale = { 0.5, 3, 0.25 }, width = { 100, 400, 20 }, alerts = { 0, 8, 1 } }   -- min, max, step

local KEYS = { "anchor", "scale", "width", "alerts" }

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

-- Settings read from the file: only well-formed fields survive.
local function clean(s)
  if type(s) ~= "table" then return nil end
  local out = {}
  local anchors = {}
  for _, a in ipairs(huds.ANCHORS) do anchors[a] = true end
  if anchors[s.anchor] then out.anchor = s.anchor end
  for k, lim in pairs(huds.LIMITS) do
    if type(s[k]) == "number" and s[k] >= lim[1] and s[k] <= lim[2] then out[k] = s[k] end
  end
  if type(s.bars) == "table" then
    out.bars = {}
    for _, b in ipairs(s.bars) do if type(b) == "string" then out.bars[#out.bars + 1] = b end end
  end
  return out
end

local function serialize(players)
  local names = {}
  for name in pairs(players) do names[#names + 1] = name end
  table.sort(names)
  local lines = { "-- lens-hud.cfg: each player's own HUD, written by lens-hub's HUD editor (tap HUD on the dashboard).",
    "-- Players not listed get the hud in lens-hub.cfg.", "return {" }
  for _, name in ipairs(names) do
    local s = players[name]
    local parts = {}
    for _, k in ipairs(KEYS) do
      if s[k] ~= nil then parts[#parts + 1] = k .. " = " .. (type(s[k]) == "string" and ("%q"):format(s[k]) or tostring(s[k])) end
    end
    if s.bars then
      local bars = {}
      for _, b in ipairs(s.bars) do bars[#bars + 1] = ("%q"):format(b) end
      parts[#parts + 1] = "bars = { " .. table.concat(bars, ", ") .. " }"
    end
    lines[#lines + 1] = ("  [%q] = { %s },"):format(name, table.concat(parts, ", "))
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

function Huds:settings(player)
  local own = player and self.players[player]
  local s = { own = own ~= nil }
  for _, k in ipairs(KEYS) do s[k] = (own and own[k] ~= nil) and own[k] or self.defaults[k] end
  if own and own.bars then
    s.bars = { table.unpack(own.bars) }
  else
    s.bars = {}
    for _, b in ipairs(self.defaults.bars or {}) do s.bars[#s.bars + 1] = b.label end
  end
  return s
end

function Huds:catalog(panels)
  local out, seen = {}, {}
  for _, b in ipairs(self.defaults.bars or {}) do
    if not seen[b.label] then out[#out + 1] = b; seen[b.label] = true end
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
  s.own = nil
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

-- A terminal's opts: its wearer's settings over the defaults, and the bars they picked, from the catalog.
function Huds:optsFor(player, catalog)
  local s = self:settings(player)
  local opts = {}
  for k, v in pairs(self.defaults) do opts[k] = v end
  for _, k in ipairs(KEYS) do opts[k] = s[k] end
  local byLabel = {}
  for _, b in ipairs(catalog) do byLabel[b.label] = b end
  local bars = {}
  for _, label in ipairs(s.bars) do if byLabel[label] then bars[#bars + 1] = byLabel[label] end end
  return opts, bars
end

function Huds:draw(m, evaluate, panels)
  local catalog = self:catalog(panels)
  local errs = {}
  local calls = 0
  for _, t in ipairs(self.terms) do
    local opts, bars = self:optsFor(t.player, catalog)
    t.hud.opts = opts
    local view = setmetatable({ hudBars = evaluate(bars), screen = t.screen }, { __index = m })
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
