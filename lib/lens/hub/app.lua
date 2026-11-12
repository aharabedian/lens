--[[ lens.hub.app: the hub program's state and reactions, without the event loop (src/lens-hub.lua has that).

  local app, err = require("lens.hub.app").new(cfg, { gpu, w, h, modem?, terminals?, boardPath?, keyboard?,
                                                        beep?, boot? })
    cfg: lens.hub.config output. err when the hub core refuses the config (bad rules).
    terminals: { [address] = Glasses Terminal }; each shows its wearer's HUD every tick (lens.hub.huds) unless
    cfg.hud is false. A HUD failure is shown on the dashboard (model.hudError) and never stops the hub.
    boardPath: lens-board.cfg (lens.hub.board: views, the dashboard's pages, players' HUDs). keyboard: whether
    one is attached (fields can be typed).
  app:start(now)                         open the port, broadcast hello, draw
  app:tick(now)                          about once a second: alerts, panel samples, beep, redraw
  app:onModem(from, port, data, now)     feed a packet to the hub core, send its replies
  app:onTouch(x, y, now, player)         tap the screen (player: who tapped), redraw
  app:onKey(char, code, now, player)     a key_down, for the open editor (only its player's)
  app:onClipboard(text, now, player)     a paste, the same way
  app:onGlasses(address, player, width, height, now)   a glasses_on: that terminal's wearer and GUI size
  app:stop()
  app:panels(now) -> the shown page's panels, evaluated (with history)
  app.page                               the dashboard page shown (an index into board:pages()); tapping a
                                         tab changes it for everyone looking at the screen
  app:evaluate(views, history?, now) -> { { label, text, frac, level, history, value, status?, dots?, hidden? }... }
                                         status: the first true status rule's level ("off": none);
                                         dots: lens.hub.format.dots; hidden: the view's `when` is false now
  app.evaluateWith(view, query, select)  the same for one view, with your own query(text) and select(text) (also
                                         on the module: require("lens.hub.app").evaluateWith)
  app.running, app.hub (lens.hub.core), app.board, app.huds (or nil), app.dash (lens.hub.dashboard), app.now

  Editors (lens.hub.editors.<kind>: hud, edit, view, data, log; their interface is in editors/hud.lua). One is open
  at a time (app.editing = { kind, player, until, ... }), for the player who opened it: only that player's taps
  and keys change anything, and it closes after EDIT_TIMEOUT seconds without one. For editors:
  app:open(kind, player, state)   open one, unless someone else has one open (app.notice says who)
  app:switch(player, state)       go to another editor (state.kind) for the same player
  app:close()
  app:mayEdit(player) -> bool     cfg.editors, when set, lists who may change the dashboard

  Beeps once when a new bad alert appears (cfg.beep). Panel history keeps one value every cfg.sample seconds.
]]

local codec = require("lens.codec")
local core = require("lens.hub.core")
local dashboard = require("lens.hub.dashboard")
local format = require("lens.hub.format")
local huds = require("lens.hub.huds")
local board = require("lens.hub.board")
local VERSION = require("lens.version")

local app = {}

local HISTORY = 120
local EDIT_TIMEOUT = 60

local EDITORS = {
  hud  = require("lens.hub.editors.hud"),
  edit = require("lens.hub.editors.edit"),
  view = require("lens.hub.editors.view"),
  data = require("lens.hub.editors.data"),
  log  = require("lens.hub.editors.log"),
}

local App = {}
App.__index = App

function app.new(cfg, env)
  local hub, err = core.new{ node = cfg.node, boot = env.boot or codec.newBoot(), token = cfg.token,
    staleAfter = cfg.staleAfter, nonCritical = cfg.nonCritical, rules = cfg.rules }
  if not hub then return nil, err end
  local self = setmetatable({ cfg = cfg, env = env, hub = hub, running = true, history = {}, nextSample = 0, now = 0,
    page = 1 }, App)
  self.dash = dashboard.new(env.gpu, env.w, env.h)
  self.board = board.new(env.boardPath, cfg)
  if env.terminals and next(env.terminals) and cfg.hud ~= false then
    self.huds = huds.new(env.terminals, cfg.hud, self.board)
  end
  self.actions = {
    ack = function(key) self.hub.alerts:ack(key) end,
    ackAll = function() self.hub.alerts:ackAll() end,
    quit = function() self.running = false end,
    page = function(_, i) self.page = i end,
  }
  for kind, E in pairs(EDITORS) do
    E.actions(self, self.actions, function(fn) return self:mine(kind, fn) end)
  end
  return self
end

---------------------------------------------------------------- editors
function App:mayEdit(player)
  if not self.cfg.editors then return true end
  for _, n in ipairs(self.cfg.editors) do if n == player then return true end end
  return false
end

function App:open(kind, player, state)
  local e = self.editing
  if e and e.player ~= player then
    self.notice = ("%s is editing (free in %ds)."):format(tostring(e.player), math.max(0, math.ceil(e["until"] - self.now)))
    return
  end
  state.kind = kind
  self:switch(player, state)
  self.notice = nil
end

function App:switch(player, state)
  state.player, state["until"] = player, self.now + EDIT_TIMEOUT
  self.editing, self.editError = state, nil
end

function App:close() self.editing, self.editError = nil, nil end

-- Wraps an editor's action: it runs only for the player who opened an editor of that kind, and keeps it open.
-- fn returning nil, err (or false, err) shows err.
function App:mine(kind, fn)
  return function(player, ...)
    local e = self.editing
    if not e or e.kind ~= kind or player ~= e.player then return end
    e["until"] = self.now + EDIT_TIMEOUT
    local ok, err = fn(e.player, ...)
    self.editError = (not ok and err) and tostring(err) or nil
  end
end

function App:editorModel(now)
  local e = self.editing
  if not e or (e.kind == "hud" and not self.huds) then return nil end
  local m = EDITORS[e.kind].model(self, e, now)
  m.kind, m.player, m.error = e.kind, e.player, self.editError
  m.closesIn = math.max(0, math.ceil(e["until"] - now))
  return m
end

-- Keys and pastes go to the open editor, from its player only.
function App:typing(player, now, method, ...)
  local e = self.editing
  local E = e and EDITORS[e.kind]
  if not (E and E[method]) or player ~= e.player then return end
  self.now = now
  e["until"] = now + EDIT_TIMEOUT
  E[method](self, e, ...)
  self.editError = nil
  if self.running then self:redraw(now, false) end
end

function App:onKey(char, code, now, player) self:typing(player, now, "key", char, code) end
function App:onClipboard(text, now, player) self:typing(player, now, "paste", text) end

---------------------------------------------------------------- panels and the HUD
-- One view's value now: { label, text, frac, level, value, dots?, hidden? }. query(text) and select(text)
-- evaluate a query and a selector (the hub's cached ones, or fresh ones for a view being typed).
function App.evaluateWith(p, query, select)
  local v = p.value and query(p.value) or nil
  local total = p.of and query(p.of) or nil
  local values
  if p.values then
    values = {}
    for name, q in pairs(p.values) do values[name] = query(q) end
  end
  local status
  if p.status then
    status = "off"
    for _, rule in ipairs(p.status) do
      local w = query(format.expand(rule[2], p.value))
      if w ~= nil and w ~= 0 then status = rule[1]; break end
    end
  end
  local text, frac, level = format.view(p, v, total, values, status)
  local out = { label = p.label, text = text, frac = frac, level = level, value = v, status = status }
  if p.dots then out.dots = format.dots(select(p.dots), p.by, p.states) end
  if p.when then
    local w = query(p.when)
    out.hidden = not (w ~= nil and w ~= 0)
  end
  return out
end

app.evaluateWith = App.evaluateWith

function App:evaluate(list, history, now)
  local query = function(text) return (self.hub:query(text, now)) end
  local select = function(text) return self.hub:select(text, now) or {} end
  local out = {}
  for i, p in ipairs(list) do
    out[i] = App.evaluateWith(p, query, select)
    out[i].history = history and history[p.label]
  end
  return out
end

function App:panels(now)
  self.page = math.max(1, math.min(self.page, #self.board:pages()))
  return self:evaluate(self.board:panels(self.page), self.history, now)
end

-- One value per panel every cfg.sample seconds; panels that are gone lose their history.
function App:sample(now)
  if now < self.nextSample then return end
  self.nextSample = now + self.cfg.sample
  local keep = {}
  for _, p in ipairs(self.board:allPanels()) do      -- every page's, so switching pages shows a history
    local h = self.history[p.label] or {}
    local v = p.value and self.hub:query(p.value, now) or nil
    h[#h + 1] = v == nil and false or v
    if #h > HISTORY then table.remove(h, 1) end
    keep[p.label] = h
  end
  self.history = keep
end

-- HUD calls in the last minute, from samples taken each tick.
function App:hudRate(now)
  local s = self.hudSamples or {}
  self.hudSamples = s
  s[#s + 1] = { now, self.huds.calls }
  while #s > 1 and now - s[1][1] > 60 do table.remove(s, 1) end
  return self.huds.calls - s[1][2]
end

function App:drawHuds(m, now)
  local ok, err = pcall(self.huds.draw, self.huds, m, function(views) return self:evaluate(views, nil, now) end,
    self.board:views())
  self.hudError = not ok and tostring(err) or self.huds.error
  self.hudPerMinute = self:hudRate(now)
end

---------------------------------------------------------------- drawing and events
function App:pageNames()
  local out = {}
  for _, pg in ipairs(self.board:pages()) do out[#out + 1] = pg.name end
  return out
end

function App:model(now)
  return {
    now = now, port = self.cfg.port, node = self.cfg.node, version = VERSION, health = self.hub:health(now),
    missingConfig = self.cfg.missing, nodes = self.hub:nodes(now),
    alerts = self.hub.alerts:list(), counts = self.hub.alerts:counts(), panels = self:panels(now),
    huds = self.huds ~= nil, editor = self:editorModel(now), notice = self.notice,
    pages = self:pageNames(), page = self.page, logged = #self.hub.alerts:history(),
  }
end

function App:redraw(now, withHud)
  self.now = now
  local m = self:model(now)
  if self.huds and withHud then self:drawHuds(m, now) end
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
  self.notice = nil
  self.dash:tap(x, y, player)
  if self.running then self:redraw(now, true) end
end

-- Whether any of these alert keys is a bad alert.
function App:anyBad(keys)
  local new = {}
  for _, key in ipairs(keys) do new[key] = true end
  for _, a in ipairs(self.hub.alerts:list()) do
    if new[a.key] and a.level == "bad" then return true end
  end
  return false
end

function App:tick(now)
  self.now = now
  if self.editing and now >= self.editing["until"] then self:close() end
  local changes = self.hub:tick(now)
  if self.cfg.beep and self.env.beep and self:anyBad(changes.new) then self.env.beep() end
  self:sample(now)
  return self:redraw(now, true)
end

function App:stop()
  if self.huds then self.huds:clear() end
  if self.env.modem then self.env.modem.close(self.cfg.port) end
  self.dash:restore()
end

return app
