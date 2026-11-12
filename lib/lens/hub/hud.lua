--[[ lens.hub.hud: the hub's model on OC Glasses (a Glasses Terminal, component "glasses"), as a small block of
  text and bars in a corner of the wearer's view.

  local h = require("lens.hub.hud").new(proxy, opts)    opts = cfg.hud (lens.hub.config has the defaults)
  h:draw(model)     the dashboard's model (lens.hub.app); widgets are made on first use, then each setter is
                    called only when its value changed, because every call is a component call
  h:clear()         remove every widget it made
  hud.rgb(hex, units) -> r, g, b   0xRRGGBB in the terminal's color units: "float" (0..1) or "byte" (0..255)

  Rows: health ("LENS OK  1 bad  2 warn"), one per panel (label, bar, value), then the newest unacknowledged
  alerts. Unused rows are hidden, not removed. Measured in game: positions are GUI pixels from the top left;
  Rect2D's setSize takes the height first; text is about 5.2 px a character per unit of setScale (and starts at
  scale 2 if setScale is never called, so the HUD always sets it). opts.scale is that setScale value.
]]

local Gui = require("lens.gui")

local hud = {}

local C = Gui.C
local HEALTH = { ok = C.good, warn = C.warn, bad = C.bad }
local CHAR, LINE, LABEL, VALUE = 5.2, 10, 8, 8    -- px per character and line at scale 1; label, value chars

function hud.rgb(hex, units)
  local r, g, b = (hex >> 16) & 0xff, (hex >> 8) & 0xff, hex & 0xff
  if units == "byte" then return r, g, b end
  return r / 255, g / 255, b / 255
end

local Hud = {}
Hud.__index = Hud

function hud.new(proxy, opts)
  opts = opts or {}
  return setmetatable({ proxy = proxy, opts = opts, slots = {}, order = {} }, Hud)
end

-- A widget by key, made on first use. kind: "text" or "rect".
function Hud:slot(key, kind)
  local s = self.slots[key]
  if not s then
    local w = kind == "text" and self.proxy.addTextLabel() or self.proxy.addRect()
    s = { w = w, state = {} }
    self.slots[key] = s
    self.order[#self.order + 1] = key
  end
  return s
end

-- Call w[method](...) unless the last call had the same arguments.
local function set(s, method, ...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local key = table.concat(parts, ",")
  if s.state[method] == key then return end
  s.state[method] = key
  s.w[method](...)
end

function Hud:color(s, hex)
  set(s, "setColor", hud.rgb(hex, self.opts.colors))
end

function Hud:alpha(s, a)
  set(s, "setAlpha", self.opts.colors == "byte" and math.floor(a * 255 + 0.5) or a)
end

function Hud:text(key, x, y, text, hex)
  local s = self:slot(key, "text")
  set(s, "setScale", self.opts.scale or 1)
  set(s, "setPosition", x, y)
  set(s, "setText", text)
  self:color(s, hex)
  set(s, "setVisible", true)
  return s
end

function Hud:rect(key, x, y, w, h, hex, alpha)
  local s = self:slot(key, "rect")
  set(s, "setPosition", x, y)
  set(s, "setSize", h, math.max(1, math.floor(w + 0.5)))    -- height first (seen in game)
  self:color(s, hex)
  if alpha then self:alpha(s, alpha) end
  set(s, "setVisible", true)
  return s
end

function Hud:hide(key)
  local s = self.slots[key]
  if s then set(s, "setVisible", false) end
end

local function cut(text, chars)
  if Gui.len(text) <= chars then return text end
  return Gui.fit(text, chars)
end

local function pickPanels(model, wanted, limit)
  if not wanted then
    local out = {}
    for i = 1, math.min(limit, #model.panels) do out[i] = model.panels[i] end
    return out
  end
  local byLabel, out = {}, {}
  for _, p in ipairs(model.panels) do byLabel[p.label] = p end
  for _, label in ipairs(wanted) do if byLabel[label] then out[#out + 1] = byLabel[label] end end
  return out
end

function Hud:draw(m)
  local o = self.opts
  local scale = o.scale or 1
  local x0, y0, width = o.x or 4, o.y or 4, o.width or 160
  local line, char = math.ceil(LINE * scale), CHAR * scale
  local used = { bg = true }
  local function mark(key) used[key] = true end
  -- The backdrop is made before any row, so it's drawn under them; it's sized once the rows are known.
  local bg = self:slot("bg", "rect")

  local c = m.counts or { bad = 0, warn = 0, unacked = 0 }
  local head = ("LENS %s"):format(({ ok = "OK", warn = "WARN", bad = "BAD" })[m.health] or "?")
  if c.bad > 0 then head = head .. ("  %d bad"):format(c.bad) end
  if c.warn > 0 then head = head .. ("  %d warn"):format(c.warn) end
  local y = y0 + 2
  self:text("head", x0 + 3, y, cut(head, math.floor((width - 6) / char)), HEALTH[m.health] or C.dim); mark("head")
  y = y + line

  local labelW, valueW = math.ceil(LABEL * char) + 2, math.ceil(VALUE * char)
  local barX, barW = x0 + 3 + labelW, width - 6 - labelW - valueW - 3
  for i, p in ipairs(pickPanels(m, o.panels, o.maxPanels or 6)) do
    local k = "p" .. i
    self:text(k .. "l", x0 + 3, y, cut(p.label, LABEL), C.dim); mark(k .. "l")
    local barColor = p.level == "bad" and C.bad or p.level == "warn" and C.warn or C.info
    if p.frac and barW > 4 then
      local frac = math.max(0, math.min(1, p.frac))
      self:rect(k .. "b", barX, y, barW, line - 3, C.line, 0.8); mark(k .. "b")
      if frac > 0 then self:rect(k .. "f", barX, y, barW * frac, line - 3, barColor, 1); mark(k .. "f") end
    end
    local valueColor = p.level == "bad" and C.bad or p.level == "warn" and C.warn or C.text
    self:text(k .. "v", x0 + width - 3 - valueW, y, cut(p.text or "-", VALUE), valueColor); mark(k .. "v")
    y = y + line
  end

  local shown = 0
  for _, a in ipairs(m.alerts or {}) do
    if shown >= (o.alerts or 3) then break end
    if not a.acked then
      shown = shown + 1
      local text = (a.level == "bad" and "! " or "· ") .. a.text
      self:text("a" .. shown, x0 + 3, y, cut(text, math.floor((width - 6) / char)), a.level == "bad" and C.bad or C.warn)
      mark("a" .. shown)
      y = y + line
    end
  end

  set(bg, "setPosition", x0, y0)
  set(bg, "setSize", y - y0 + 2, width)
  self:color(bg, C.bg)
  self:alpha(bg, o.alpha or 0.6)
  set(bg, "setVisible", true)

  for _, key in ipairs(self.order) do
    if not used[key] then self:hide(key) end
  end
end

function Hud:clear()
  for _, key in ipairs(self.order) do
    local s = self.slots[key]
    pcall(function() self.proxy.removeObject(s.w.getID()) end)
  end
  self.slots, self.order = {}, {}
end

return hud
