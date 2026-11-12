--[[ lens.hub.app: the hub program's state and reactions, without the event loop (src/lens-hub.lua has that).

  local app, err = require("lens.hub.app").new(cfg, { gpu, w, h, modem?, terminals?, hudPath?, beep?, boot? })
    terminals: { [address] = Glasses Terminal }; each shows its wearer's HUD every tick (lens.hub.huds) unless
    cfg.hud is false. hudPath: the players' HUD settings file. A HUD failure is shown on the dashboard
    (model.hudError) and never stops the hub.
    cfg: lens.hub.config output. err when the hub core refuses the config (bad rules).
  app:start(now)                         open the port, broadcast hello, draw
  app:onModem(from, port, data, now)     feed a packet to the hub core, send its replies
  app:onTouch(x, y, now, player)         tap the dashboard (player: who tapped), redraw
  app:onGlasses(address, player, width, height, now)   a glasses_on: that terminal's wearer and GUI size

  The HUD editor: the dashboard's HUD button opens it for the player who tapped; only that player's taps
  change anything, and it closes after EDIT_TIMEOUT seconds without one (model.editor while open).
  app:tick(now)                          about once a second: alerts, panel samples, beep, redraw
  app:stop()
  app.running, app.hub (lens.hub.core), app.dash (lens.hub.dashboard)
  app:panels(now) -> the model's panels (also used by tests)

  Beeps once when a new bad alert appears (cfg.beep). Panel history keeps one value every cfg.sample seconds.
]]

local codec = require("lens.codec")
local core = require("lens.hub.core")
local dashboard = require("lens.hub.dashboard")
local config = require("lens.hub.config")
local format = require("lens.hub.format")
local huds = require("lens.hub.huds")
local VERSION = require("lens.version")

local app = {}

local HISTORY = 120
local EDIT_TIMEOUT = 60

local App = {}
App.__index = App

function app.new(cfg, env)
  local hub, err = core.new{ node = cfg.node, boot = env.boot or codec.newBoot(), token = cfg.token,
    staleAfter = cfg.staleAfter, nonCritical = cfg.nonCritical, rules = cfg.rules }
  if not hub then return nil, err end
  local self = setmetatable({ cfg = cfg, env = env, hub = hub, running = true, history = {}, nextSample = 0 }, App)
  self.dash = dashboard.new(env.gpu, env.w, env.h)
  if env.terminals and next(env.terminals) and cfg.hud ~= false then
    self.huds = huds.new(env.terminals, cfg.hud, env.hudPath)
  end
  for i = 1, #cfg.panels do self.history[i] = {} end
  self.actions = {
    ack = function(key) self.hub.alerts:ack(key) end,
    ackAll = function() self.hub.alerts:ackAll() end,
    quit = function() self.running = false end,
    hud = function(player) self.editing = { player = player, ["until"] = self.now + EDIT_TIMEOUT, block = 1, step = 8 } end,
  }
  self:editorActions()
  return self
end

-- The HUD editor's buttons. Each gets the tapping player; anyone else's taps do nothing. Changes go to the
-- block being edited (editing.block).
local STEPS = { 1, 8, 32 }

function App:editorActions()
  local a = self.actions
  local function mine(fn)
    return function(player, ...)
      local e = self.editing
      if not e or player ~= e.player then return end
      e["until"] = self.now + EDIT_TIMEOUT
      local ok, err = fn(e.player, ...)
      self.editError = (ok == false) and ("can't save: " .. tostring(err)) or nil
    end
  end
  local function clamp(v, lim) return math.max(lim[1], math.min(lim[2], v)) end
  -- fn(settings, block, ...) edits the player's settings; the block is the one being edited.
  local function change(fn) return mine(function(player, ...)
    local args = table.pack(...)
    return self.huds:change(player, function(s)
      local i = math.min(self.editing.block, #s.blocks)
      self.editing.block = i
      fn(s, s.blocks[i], table.unpack(args, 1, args.n))
    end)
  end) end
  a.hudDone = mine(function() self.editing = nil end)
  a.hudReset = mine(function(player) self.editing.block = 1; return self.huds:reset(player) end)
  a.hudBlock = mine(function(_, i) self.editing.block = i end)
  a.hudStepSize = mine(function()
    local e = self.editing
    for i, v in ipairs(STEPS) do if v == e.step then e.step = STEPS[i % #STEPS + 1]; return end end
    e.step = STEPS[1]
  end)
  a.hudBlockAdd = change(function(s)
    if #s.blocks >= huds.LIMITS.blocks[2] then return end
    local x, y = config.offset("top-left")
    s.blocks[#s.blocks + 1] = { anchor = "top-left", x = x, y = y, width = 160, elements = {} }
    self.editing.block = #s.blocks
  end)
  a.hudBlockRemove = change(function(s)
    if #s.blocks <= 1 then return end
    table.remove(s.blocks, self.editing.block)
    self.editing.block = math.max(1, self.editing.block - 1)
  end)
  a.hudToggle = change(function(_, b, label)
    for i, el in ipairs(b.elements) do if el.view == label then table.remove(b.elements, i); return end end
    b.elements[#b.elements + 1] = { kind = "bar", view = label }
  end)
  a.hudKind = change(function(_, b, i)
    local el = b.elements[i]
    if el and (el.kind == "bar" or el.kind == "text") then el.kind = el.kind == "bar" and "text" or "bar" end
  end)
  a.hudMove = change(function(_, b, i, dir)
    local j = i + dir
    if b.elements[i] and b.elements[j] then b.elements[i], b.elements[j] = b.elements[j], b.elements[i] end
  end)
  a.hudAlerts = change(function(_, b, dir)
    for i, el in ipairs(b.elements) do
      if el.kind == "alerts" then
        el.count = clamp(el.count + dir, huds.LIMITS.count)
        if el.count == 0 then table.remove(b.elements, i) end
        return
      end
    end
    if dir > 0 then b.elements[#b.elements + 1] = { kind = "alerts", count = 1 } end
  end)
  a.hudGap = change(function(_, b) b.elements[#b.elements + 1] = { kind = "gap" } end)
  a.hudRemove = change(function(_, b, i) table.remove(b.elements, i) end)
  a.hudAnchor = change(function(_, b, anchor)
    b.anchor = anchor
    b.x, b.y = config.offset(anchor)
  end)
  a.hudNudge = change(function(_, b, dx, dy)
    b.x, b.y = b.x + dx * self.editing.step, b.y + dy * self.editing.step
  end)
  a.hudWidth = change(function(_, b, dir) b.width = clamp(b.width + dir * huds.LIMITS.width[3], huds.LIMITS.width) end)
  a.hudScale = change(function(s, _, dir) s.scale = clamp(s.scale + dir * huds.LIMITS.scale[3], huds.LIMITS.scale) end)
end

-- Views (panels, HUD bars and texts) evaluated for display (lens.hub.format).
function App:evaluate(list, history, now)
  local out = {}
  for i, p in ipairs(list) do
    local v = self.hub:query(p.value, now)
    local total = p.of and self.hub:query(p.of, now) or nil
    local text, frac, level = format.view(p, v, total)
    out[i] = { label = p.label, text = text, frac = frac, level = level, history = history and history[i], value = v }
  end
  return out
end

function App:panels(now) return self:evaluate(self.cfg.panels, self.history, now) end

-- HUD calls in the last minute, from samples taken each tick.
function App:hudRate(now)
  if not self.huds then return nil end
  local s = self.hudSamples or {}
  self.hudSamples = s
  s[#s + 1] = { now, self.huds.calls }
  while #s > 1 and now - s[1][1] > 60 do table.remove(s, 1) end
  return self.huds.calls - s[1][2]
end

function App:editorModel()
  local e = self.editing
  if not e or not self.huds then return nil end
  local s = self.huds:settings(e.player)
  e.block = math.min(e.block, #s.blocks)
  local b = s.blocks[e.block]
  local rows, used = {}, {}
  for i, el in ipairs(b.elements) do
    rows[#rows + 1] = { index = i, kind = el.kind, label = el.view, count = el.count }
    if el.view then used[el.view] = true end
  end
  local hidden = {}
  for _, v in ipairs(self.huds:catalog(self.cfg.panels)) do
    if not used[v.label] then hidden[#hidden + 1] = v.label end
  end
  return { player = e.player, own = s.own, scale = s.scale, blocks = #s.blocks, block = e.block,
    anchor = b.anchor, x = b.x, y = b.y, width = b.width, rows = rows, hidden = hidden, step = e.step,
    wearing = self.huds:wearing(e.player), error = self.editError, closesIn = math.max(0, math.ceil(e["until"] - self.now)) }
end

function App:model(now)
  return {
    now = now, port = self.cfg.port, node = self.cfg.node, version = VERSION, health = self.hub:health(now),
    missingConfig = self.cfg.missing, nodes = self.hub:nodes(now),
    alerts = self.hub.alerts:list(), counts = self.hub.alerts:counts(), panels = self:panels(now),
    huds = self.huds ~= nil, editor = self:editorModel(),
  }
end

function App:redraw(now, withHud)
  self.now = now
  local m = self:model(now)
  if self.huds and withHud then
    local ok, err = pcall(self.huds.draw, self.huds, m, function(bars) return self:evaluate(bars, nil, now) end,
      self.cfg.panels)
    self.hudError = not ok and tostring(err) or self.huds.error
    self.hudPerMinute = self:hudRate(now)
  end
  m.hudError, m.hudPerMinute = self.hudError, self.hudPerMinute
  self.dash:draw(m, self.actions)
  return m
end

function App:start(now)
  self.now = now
  local modem = self.env.modem
  if modem then
    modem.open(self.cfg.port)
    modem.broadcast(self.cfg.port, self.hub:hello())
  end
  self:tick(now)
end

function App:onModem(from, port, data, now)
  if port ~= self.cfg.port or type(data) ~= "string" then return end
  for _, r in ipairs(self.hub:receive(data, from, now)) do
    if self.env.modem then self.env.modem.send(r.to, self.cfg.port, r.data) end
  end
end

function App:onGlasses(address, player, w, h, now)
  if not self.huds then return end
  self.huds:onGlasses(address, player, w, h)
  if self.running then self:redraw(now, true) end
end

function App:onTouch(x, y, now, player)
  self.now = now
  self.dash:tap(x, y, player)
  if self.running then self:redraw(now, true) end
end

function App:tick(now)
  self.now = now
  if self.editing and now >= self.editing["until"] then self.editing, self.editError = nil, nil end
  local changes = self.hub:tick(now)
  if self.cfg.beep and self.env.beep and #changes.new > 0 then
    local bad = false
    for _, a in ipairs(self.hub.alerts:list()) do
      for _, key in ipairs(changes.new) do if a.key == key and a.level == "bad" then bad = true end end
    end
    if bad then self.env.beep() end
  end
  if now >= self.nextSample then
    self.nextSample = now + self.cfg.sample
    for i, p in ipairs(self.cfg.panels) do
      local h = self.history[i]
      local v = self.hub:query(p.value, now)
      h[#h + 1] = v == nil and false or v
      if #h > HISTORY then table.remove(h, 1) end
    end
  end
  return self:redraw(now, true)
end

function App:stop()
  if self.huds then self.huds:clear() end
  if self.env.modem then self.env.modem.close(self.cfg.port) end
  self.dash:restore()
end

return app
