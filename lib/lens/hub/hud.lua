--[[ lens.hub.hud: the hub's state on OC Glasses (a Glasses Terminal, component "glasses"): a few bars and the
  newest alerts, small, in a corner of the wearer's view.

  local h = require("lens.hub.hud").new(proxy, opts)    opts = cfg.hud (lens.hub.config has the defaults)
  h:draw(model)     model: the dashboard's model plus model.hudBars (bars evaluated like panels: label, text,
                    frac, level). Widgets are made on first use; afterwards a setter is called only when its
                    value changed, because every call is a component call.
  h:clear()         remove every widget it made
  h.calls           component calls made so far (shown on the dashboard, to see what the HUD costs)
  hud.rgb(hex, units) -> r, g, b   0xRRGGBB as "float" (0..1, OC Glasses) or "byte" (0..255)

  Layout, top to bottom, with a thin strip down the left in the overall health's color:
    one row per bar: label, bar (fill colored by its level), value
    the newest unacknowledged alerts: a colored "!" and the text; "+N more" when there are more
    "LENS OK" only when there are no bars and no alerts, so the strip isn't alone
  Measured in game: positions are GUI pixels from the top left; Rect2D setSize takes the height first; text is
  about 5.2 px a character per unit of setScale (and starts at scale 2 unless set, so the HUD always sets it).
]]

local hud = {}

-- Palette: quiet unless something needs attention.
hud.COLORS = {
  text = 0xeef1f4, dim = 0xb4bec8, track = 0x262d36, fill = 0x4fb8a8, backdrop = 0x0d1117,
  ok = 0x4fb8a8, warn = 0xf0b03c, bad = 0xe5534b, stale = 0x8a939c,
}
local P = hud.COLORS
local CHAR, LINE = 5.2, 11          -- px per character and per row at scale 1

function hud.rgb(hex, units)
  local r, g, b = (hex >> 16) & 0xff, (hex >> 8) & 0xff, hex & 0xff
  if units == "byte" then return r, g, b end
  return r / 255, g / 255, b / 255
end

local Hud = {}
Hud.__index = Hud

function hud.new(proxy, opts)
  return setmetatable({ proxy = proxy, opts = opts or {}, slots = {}, order = {}, calls = 0 }, Hud)
end

-- A widget by key, made on first use. kind: "text" or "rect".
function Hud:slot(key, kind)
  local s = self.slots[key]
  if not s then
    self.calls = self.calls + 1
    local w = kind == "text" and self.proxy.addTextLabel() or self.proxy.addRect()
    s = { w = w, state = {} }
    self.slots[key] = s
    self.order[#self.order + 1] = key
  end
  return s
end

-- Call w[method](...) unless the last call had the same arguments.
function Hud:set(s, method, ...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local key = table.concat(parts, ",")
  if s.state[method] == key then return end
  s.state[method] = key
  self.calls = self.calls + 1
  s.w[method](...)
end

function Hud:paint(s, hex, alpha)
  self:set(s, "setColor", hud.rgb(hex, self.opts.colors))
  if alpha then self:set(s, "setAlpha", self.opts.colors == "byte" and math.floor(alpha * 255 + 0.5) or alpha) end
end

function Hud:text(key, x, y, text, hex)
  local s = self:slot(key, "text")
  self:set(s, "setScale", self.opts.scale or 1)
  self:set(s, "setPosition", x, y)
  self:set(s, "setText", text)
  self:paint(s, hex)
  self:set(s, "setVisible", true)
end

function Hud:rect(key, x, y, w, h, hex, alpha)
  local s = self:slot(key, "rect")
  self:set(s, "setPosition", x, y)
  self:set(s, "setSize", math.max(1, math.floor(h + 0.5)), math.max(1, math.floor(w + 0.5)))  -- height first
  self:paint(s, hex, alpha)
  self:set(s, "setVisible", true)
end

local function cut(text, chars)
  text = tostring(text or "")
  if (utf8.len(text) or #text) <= chars then return text end
  local n, out = 0, {}
  for _, c in utf8.codes(text) do
    n = n + 1
    if n >= chars then break end
    out[#out + 1] = utf8.char(c)
  end
  return table.concat(out) .. "…"
end

function Hud:draw(m)
  local o = self.opts
  local scale = o.scale or 1
  local x0, y0, width = o.x or 4, o.y or 20, o.width or 160
  local line, char = math.ceil(LINE * scale), CHAR * scale
  local used = { bg = true, strip = true }
  local function mark(key) used[key] = true end
  -- Made before any row, so they're drawn under the rows; sized once the rows are known.
  local bg, strip = self:slot("bg", "rect"), self:slot("strip", "rect")

  local tx = x0 + 6                              -- text starts right of the strip
  local inner = width - 8
  local y = y0 + 2
  local labelChars, valueChars = 6, 6
  local labelW, valueW = math.ceil(labelChars * char) + 3, math.ceil(valueChars * char)
  local barX, barW = tx + labelW, inner - labelW - valueW - 4
  local barH = math.max(3, math.floor(line * 0.5))

  local rows = 0
  for i, b in ipairs(m.hudBars or {}) do
    local k = "b" .. i
    self:text(k .. "l", tx, y, cut(b.label, labelChars), P.dim); mark(k .. "l")
    local barY = y + math.floor((line - 2 - barH) / 2)
    self:rect(k .. "t", barX, barY, barW, barH, P.track, 0.85); mark(k .. "t")
    local level = b.level and P[b.level] or P.fill
    if b.frac and b.frac > 0 then
      self:rect(k .. "f", barX, barY, barW * math.min(1, b.frac), barH, level, 1); mark(k .. "f")
    end
    self:text(k .. "v", x0 + width - 2 - valueW, y, cut(b.text or "-", valueChars),
      b.level and P[b.level] or P.text); mark(k .. "v")
    y, rows = y + line, rows + 1
  end

  local unacked = {}
  for _, a in ipairs(m.alerts or {}) do if not a.acked then unacked[#unacked + 1] = a end end
  local limit = o.alerts or 3
  for i = 1, math.min(limit, #unacked) do
    local a = unacked[i]
    self:text("a" .. i .. "i", tx, y, "!", a.level == "bad" and P.bad or P.warn); mark("a" .. i .. "i")
    self:text("a" .. i, tx + math.ceil(2 * char), y, cut(a.text, math.floor((inner - 2 * char) / char)), P.text)
    mark("a" .. i)
    y, rows = y + line, rows + 1
  end
  if #unacked > limit then
    self:text("more", tx, y, ("+%d more"):format(#unacked - limit), P.dim); mark("more")
    y, rows = y + line, rows + 1
  end
  if rows == 0 then
    self:text("ok", tx, y, "LENS " .. ((m.health or "ok"):upper()), P.dim); mark("ok")
    y = y + line
  end

  local height = y - y0
  self:set(bg, "setPosition", x0, y0)
  self:set(bg, "setSize", height, width)
  self:paint(bg, P.backdrop, o.alpha or 0.35)
  self:set(bg, "setVisible", (o.alpha or 0.35) > 0)
  self:set(strip, "setPosition", x0, y0)
  self:set(strip, "setSize", height, 2)
  self:paint(strip, P[m.health] or P.stale, 1)
  self:set(strip, "setVisible", true)

  for _, key in ipairs(self.order) do
    if not used[key] then self:set(self.slots[key], "setVisible", false) end
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
