--[[ lens.hub.app: the hub program's state and reactions, without the event loop (src/lens-hub.lua has that).

  local app, err = require("lens.hub.app").new(cfg, { gpu, w, h, modem?, glasses?, beep?, boot? })
    glasses: a Glasses Terminal; the HUD draws there each tick unless cfg.hud is false. A HUD failure is
    shown on the dashboard (model.hudError) and never stops the hub.
    cfg: lens.hub.config output. err when the hub core refuses the config (bad rules).
  app:start(now)                         open the port, broadcast hello, draw
  app:onModem(from, port, data, now)     feed a packet to the hub core, send its replies
  app:onTouch(x, y, now)                 tap the dashboard, redraw
  app:onGlasses(width, height, now)      a glasses_on: the wearer's GUI size, to place the HUD by its anchor
  app:tick(now)                          about once a second: alerts, panel samples, beep, redraw
  app:stop()
  app.running, app.hub (lens.hub.core), app.dash (lens.hub.dashboard)
  app:panels(now) -> the model's panels (also used by tests)

  Beeps once when a new bad alert appears (cfg.beep). Panel history keeps one value every cfg.sample seconds.
]]

local codec = require("lens.codec")
local core = require("lens.hub.core")
local dashboard = require("lens.hub.dashboard")
local hud = require("lens.hub.hud")
local VERSION = require("lens.version")

local app = {}

local HISTORY = 120

local function fmt(v)
  if v == nil then return "–" end
  local a = math.abs(v)
  for _, u in ipairs({ { 1e12, "T" }, { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" } }) do
    if a >= u[1] then return (("%.1f"):format(v / u[1]):gsub("%.0$", "")) .. u[2] end
  end
  if v == math.floor(v) then return tostring(math.floor(v)) end
  return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

local function level(p, v)
  if v == nil then return nil end
  if (p.badAbove and v >= p.badAbove) or (p.badBelow and v <= p.badBelow) then return "bad" end
  if (p.warnAbove and v >= p.warnAbove) or (p.warnBelow and v <= p.warnBelow) then return "warn" end
  return nil
end

local App = {}
App.__index = App

function app.new(cfg, env)
  local hub, err = core.new{ node = cfg.node, boot = env.boot or codec.newBoot(), token = cfg.token,
    staleAfter = cfg.staleAfter, nonCritical = cfg.nonCritical, rules = cfg.rules }
  if not hub then return nil, err end
  local self = setmetatable({ cfg = cfg, env = env, hub = hub, running = true, history = {}, nextSample = 0 }, App)
  self.dash = dashboard.new(env.gpu, env.w, env.h)
  if env.glasses and cfg.hud ~= false then self.hud = hud.new(env.glasses, cfg.hud) end
  for i = 1, #cfg.panels do self.history[i] = {} end
  self.actions = {
    ack = function(key) self.hub.alerts:ack(key) end,
    ackAll = function() self.hub.alerts:ackAll() end,
    quit = function() self.running = false end,
  }
  return self
end

-- Panels (or HUD bars, same form) evaluated for display.
function App:evaluate(list, history, now)
  local out = {}
  for i, p in ipairs(list) do
    local v = self.hub:query(p.value, now)
    local unit = p.unit and (" " .. p.unit) or ""
    local text, frac
    if p.of then
      local total = self.hub:query(p.of, now)
      text = fmt(v) .. "/" .. fmt(total) .. unit
      frac = (v and total and total > 0) and v / total or nil
    elseif p.percent then
      text = v and (math.floor(v * 100 + 0.5) .. "%") or "–"
      frac = v
    else
      text = fmt(v) .. (v and unit or "")
      frac = (v and p.max) and v / p.max or nil
    end
    out[i] = { label = p.label, text = text, frac = frac, level = level(p, v), history = history and history[i], value = v }
  end
  return out
end

function App:panels(now) return self:evaluate(self.cfg.panels, self.history, now) end

-- HUD calls in the last minute, from samples taken each tick.
function App:hudRate(now)
  if not self.hud then return nil end
  local s = self.hudSamples or {}
  self.hudSamples = s
  s[#s + 1] = { now, self.hud.calls }
  while #s > 1 and now - s[1][1] > 60 do table.remove(s, 1) end
  return self.hud.calls - s[1][2]
end

function App:model(now)
  return {
    now = now, port = self.cfg.port, node = self.cfg.node, version = VERSION, health = self.hub:health(now),
    missingConfig = self.cfg.missing, nodes = self.hub:nodes(now),
    alerts = self.hub.alerts:list(), counts = self.hub.alerts:counts(), panels = self:panels(now),
  }
end

function App:redraw(now, withHud)
  local m = self:model(now)
  if self.hud and withHud then
    m.hudBars = self:evaluate(self.cfg.hud.bars or {}, nil, now)
    m.screen = self.screen
    local ok, err = pcall(self.hud.draw, self.hud, m)
    self.hudError = not ok and tostring(err) or nil
    self.hudPerMinute = self:hudRate(now)
  end
  m.hudError, m.hudPerMinute = self.hudError, self.hudPerMinute
  self.dash:draw(m, self.actions)
  return m
end

function App:start(now)
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

function App:onGlasses(w, h, now)
  if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
    self.screen = { w = w, h = h }
    if self.running then self:redraw(now, true) end
  end
end

function App:onTouch(x, y, now)
  self.dash:tap(x, y)
  if self.running then self:redraw(now, true) end
end

function App:tick(now)
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
  if self.hud then pcall(self.hud.clear, self.hud) end
  if self.env.modem then self.env.modem.close(self.cfg.port) end
  self.dash:restore()
end

return app
