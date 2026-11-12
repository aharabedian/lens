--[[ lens.hub.hud: the hub's state on OC Glasses (a Glasses Terminal, component "glasses"): a few bars and the
  newest alerts, small, in a corner of the wearer's view.

  local h = require("lens.hub.hud").new(proxy, opts)    opts = cfg.hud (lens.hub.config has the defaults)
  h:draw(model)     model: the dashboard's model plus model.screen = { w, h } (the wearer's GUI size, from
                    glasses_on; default 854 x 480) and model.hudBlocks = { { anchor, x, y, width, items }... },
                    items evaluated: { kind = "bar" | "text", label, text, frac, level, dots? } | { kind =
                    "alerts", count } | { kind = "gap" }. An item with dots shows its label and a colored dot
                    each, whatever its kind. Without hudBlocks: one block placed as opts.blocks[1], with
                    model.hudBars then the alerts. Widgets are made on first use; afterwards a setter is called
                    only when its value changed, because every call is a component call.
  opts              scale, alpha, colors (lens.hub.config's hud)
  hud.place(block, w, h, screen) -> x, y   a block's top left: its anchor (one of nine) plus x, y (right and
                    down positive), kept on screen
  h:clear()         remove every widget it made
  h.calls           component calls made so far (shown on the dashboard, to see what the HUD costs)
  hud.rgb(hex, units) -> r, g, b   0xRRGGBB as "float" (0..1, OC Glasses) or "byte" (0..255)

  Each block, top to bottom, with a faint backdrop and a thin strip down the left in the overall health's color:
    bar: label, bar (fill colored by its level), value        text: label, then the value at the right, colored
    alerts: the newest unacknowledged ones, a colored "!" and the text, then "+N more"; gap: half a row
    "LENS OK" only when a block has nothing to show, so the strip isn't alone
  Measured in game: positions are GUI pixels from the top left; Rect2D setSize takes the height first; text is
  about 5.2 px a character per unit of setScale (and starts at scale 2 unless set, so the HUD always sets it).
]]

local unicode = require("unicode")

local hud = {}

-- Palette: quiet unless something needs attention.
hud.COLORS = {
  text = 0xeef1f4, dim = 0xb4bec8, track = 0x262d36, fill = 0x4fb8a8, backdrop = 0x0d1117,
  ok = 0x4fb8a8, good = 0x5cc87a, warn = 0xf0b03c, bad = 0xe5534b, stale = 0x8a939c,
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
  if unicode.len(text) <= chars then return text end
  return unicode.sub(text, 1, chars - 1) .. "…"
end

hud.SCREEN = { w = 854, h = 480 }    -- until a glasses_on says otherwise (2560 x 1440 at GUI scale 3)

-- Where a block of w x h goes for its anchor and offset, kept on screen.
function hud.place(b, w, h, screen)
  local a = b.anchor or "top-right"
  local x = a:find("left", 1, true) and 0 or a:find("right", 1, true) and (screen.w - w) or (screen.w - w) / 2
  local y = a:find("^top") and 0 or a:find("^bottom") and (screen.h - h) or (screen.h - h) / 2
  x, y = x + (b.x or 0), y + (b.y or 0)
  x = math.max(0, math.min(screen.w - w, x))
  y = math.max(0, math.min(screen.h - h, y))
  return math.floor(x), math.floor(y)
end

local function unackedOf(m)
  local out = {}
  for _, a in ipairs(m.alerts or {}) do if not a.acked then out[#out + 1] = a end end
  return out
end

-- The rows an element takes (alerts: those shown, then "+N more").
local function rowsOf(item, unacked)
  if item.kind == "alerts" then
    local limit = item.count or 3
    if limit <= 0 then return 0 end
    return math.min(limit, #unacked) + (#unacked > limit and 1 or 0)
  elseif item.kind == "gap" then
    return 0.5
  end
  return 1
end

function Hud:block(i, b, m, unacked, used)
  local o = self.opts
  local scale = o.scale or 1
  local width = b.width or 160
  local line, char = math.ceil(LINE * scale), CHAR * scale
  local screen = m.screen or hud.SCREEN
  local rows = 0
  for _, item in ipairs(b.items) do rows = rows + rowsOf(item, unacked) end
  local empty = rows == 0
  if empty then rows = 1 end
  local x0, y0 = hud.place(b, width, math.floor(rows * line + 2), screen)
  local p = "k" .. i .. ":"
  local function mark(key) used[p .. key] = true; return p .. key end
  -- Made before any row, so they're drawn under the rows; sized once the rows are known.
  local bg, strip = self:slot(mark("bg"), "rect"), self:slot(mark("strip"), "rect")

  local tx = x0 + 6                              -- text starts right of the strip
  local inner = width - 8
  local y = y0 + 2
  local labelChars, valueChars = 6, 6
  local labelW, valueW = math.ceil(labelChars * char) + 3, math.ceil(valueChars * char)
  local barX, barW = tx + labelW, inner - labelW - valueW - 4
  local barH = math.max(3, math.floor(line * 0.5))
  local right = x0 + width - 2

  for e, item in ipairs(b.items) do
    local k = "e" .. e
    if item.kind == "bar" then
      self:text(mark(k .. "l"), tx, y, cut(item.label, labelChars), P.dim)
      local barY = y + math.floor((line - 2 - barH) / 2)
      self:rect(mark(k .. "t"), barX, barY, barW, barH, P.track, 0.85)
      local color = item.level and P[item.level] or P.fill
      if item.frac and item.frac > 0 then
        self:rect(mark(k .. "f"), barX, barY, barW * math.min(1, item.frac), barH, color, 1)
      end
      self:text(mark(k .. "v"), right - valueW, y, cut(item.text or "-", valueChars), item.level and P[item.level] or P.text)
      y = y + line
    elseif item.dots then
      -- State dots: the label, then a dot per item in its level's color, as many as fit.
      self:text(mark(k .. "l"), tx, y, cut(item.label, labelChars), P.dim)
      local dx = tx + labelW
      local fit = math.max(0, math.floor((right - dx) / (2 * char)))
      for d = 1, math.min(#item.dots, fit) do
        local dot = item.dots[d]
        self:text(mark(k .. "d" .. d), dx + math.floor((d - 1) * 2 * char), y, "●", dot.level and P[dot.level] or P.stale)
      end
      y = y + line
    elseif item.kind == "text" then
      local value = cut(item.text or "-", math.max(4, math.floor(inner / char) - 4))
      local vw = math.ceil(unicode.len(value) * char)
      self:text(mark(k .. "v"), right - vw, y, value, item.level and P[item.level] or P.text)
      local room = math.floor((right - vw - tx - char) / char)
      if room >= 2 then self:text(mark(k .. "l"), tx, y, cut(item.label, room), P.dim) end
      y = y + line
    elseif item.kind == "alerts" then
      local limit = item.count or 3
      for a = 1, math.min(limit, #unacked) do
        local al = unacked[a]
        self:text(mark(k .. "a" .. a .. "i"), tx, y, "!", al.level == "bad" and P.bad or P.warn)
        self:text(mark(k .. "a" .. a), tx + math.ceil(2 * char), y, cut(al.text, math.floor((inner - 2 * char) / char)), P.text)
        y = y + line
      end
      if limit > 0 and #unacked > limit then
        self:text(mark(k .. "more"), tx, y, ("+%d more"):format(#unacked - limit), P.dim)
        y = y + line
      end
    elseif item.kind == "gap" then
      y = y + math.floor(line / 2)
    end
  end
  if empty then
    self:text(mark("ok"), tx, y, "LENS " .. ((m.health or "ok"):upper()), P.dim)
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
end

function Hud:draw(m)
  local o = self.opts
  local blocks = m.hudBlocks
  if not blocks then
    -- One block from the opts' first block (or the old opts), with m.hudBars then the alerts.
    local first = (o.blocks and o.blocks[1]) or {}
    local items = {}
    for _, bar in ipairs(m.hudBars or {}) do
      local it = setmetatable({ kind = "bar" }, { __index = bar })
      items[#items + 1] = it
    end
    items[#items + 1] = { kind = "alerts", count = o.alerts or 3 }
    blocks = { { anchor = first.anchor or o.anchor, x = first.x, y = first.y, width = first.width or o.width, items = items } }
  end
  local unacked = unackedOf(m)
  local used = {}
  for i, b in ipairs(blocks) do self:block(i, b, m, unacked, used) end
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
