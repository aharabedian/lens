--[[ lens.hub.frame: one screenful being built: text segments per row and touch targets, plus the small widgets
  every page uses. lens.hub.dashboard turns a frame into GPU calls; pages (lens.hub.pages.*) fill it.

  local frame = require("lens.hub.frame")
  local f = frame.new(w, h)
  f.w, f.h, f.rows[y] = { bg, segs = { { x, text, fg, bg }... } }, f.hits = { { x1, y1, x2, y2, fn }... }
  f:text(x, y, s, fg?, bg?)          text, cut at the right edge
  f:rowBg(y, bg)                     a row's background
  f:hit(x1, y1, x2, y2, fn)          a touch target; fn(player) runs when it's tapped (the last one made wins)
  f:button(x, y, label, fn?, bg?) -> the x after it (one column of gap)
  f:heading(x, y, text, width)
  f:chips(x, y, width, { { label, fn, bg }... }) -> the row after the last   buttons, wrapping at width
  f:stepper(x, y, label, value, minus, plus)    label, -, value, +
  f:dots(x, y, width, dots) -> columns used    state dots (lens.hub.format.dots), colored by level; "+N" when
                                             they don't all fit
  f:editorHeader(title, { { label, fn, bg? }... })   an editor's top row: LENS, title, buttons on the right
  f:editorFooter(e, what?)           e.error in red, or who the editor is for and when it closes (what: the
                                     verb, default "can change this")
  frame.C                            the palette (lens.gui)
  frame.levelColor(level, default)   bad, warn, good and off as colors; anything else: default
  frame.ago(seconds) -> "45s", "12m", "2h05m"
]]

local Gui = require("lens.gui")

local frame = {}

local C = Gui.C
frame.C = C

function frame.levelColor(level, default)
  if level == "bad" then return C.bad end
  if level == "warn" then return C.warn end
  if level == "good" then return C.good end
  if level == "off" then return C.dim end
  return default
end

function frame.ago(s)
  s = math.max(0, math.floor(s or 0))
  if s < 60 then return s .. "s" end
  if s < 3600 then return (s // 60) .. "m" end
  return ("%dh%02dm"):format(s // 3600, (s % 3600) // 60)
end

local Frame = {}
Frame.__index = Frame

function frame.new(w, h)
  local rows = {}
  for y = 1, h do rows[y] = { bg = C.bg, segs = {} } end
  return setmetatable({ w = w, h = h, rows = rows, hits = {} }, Frame)
end

function Frame:text(x, y, s, fg, bg)
  if y < 1 or y > self.h or x > self.w then return end
  local room = self.w - x + 1
  if Gui.len(s) > room then s = Gui.fit(s, room) end
  local segs = self.rows[y].segs
  segs[#segs + 1] = { x, s, fg or C.text, bg or self.rows[y].bg }
end

function Frame:rowBg(y, bg) if self.rows[y] then self.rows[y].bg = bg end end
function Frame:hit(x1, y1, x2, y2, fn) self.hits[#self.hits + 1] = { x1, y1, x2, y2, fn } end

function Frame:button(x, y, label, fn, color)
  local s = " " .. label .. " "
  self:text(x, y, s, C.text, color or C.btn)
  if fn then self:hit(x, y, x + Gui.len(s) - 1, y, fn) end
  return x + Gui.len(s) + 1
end

function Frame:heading(x, y, text, width) self:text(x, y, Gui.fit(text, width), C.accent) end

function Frame:chips(x, y, width, items)
  local cx = x
  for _, it in ipairs(items) do
    local w = Gui.len(it[1]) + 3
    if cx > x and cx + w > x + width then cx, y = x, y + 1 end
    cx = self:button(cx, y, it[1], it[2], it[3])
  end
  return y + 1
end

function Frame:stepper(x, y, label, value, minus, plus)
  self:text(x, y, Gui.fit(label, 8), C.dim)
  self:button(x + 9, y, "-", minus)
  self:text(x + 13, y, Gui.rfit(value, 5), C.text)
  self:button(x + 19, y, "+", plus)
end

function Frame:dots(x, y, width, dots)
  local fit = #dots
  if fit * 2 - 1 > width then fit = math.max(0, (width - 4) // 2) end
  for i = 1, fit do self:text(x + (i - 1) * 2, y, "●", frame.levelColor(dots[i].level, C.dim)) end
  local used = math.max(0, fit * 2 - 1)
  if fit < #dots then
    local more = ("+%d"):format(#dots - fit)
    self:text(x + used + 1, y, more, C.dim)
    used = used + 1 + Gui.len(more)
  end
  return used
end

function Frame:editorHeader(title, buttons)
  self:rowBg(1, C.panel)
  self:text(2, 1, "LENS", C.accent, C.panel)
  local x = self.w
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    x = x - Gui.len(b[1]) - 3
    self:button(x, 1, b[1], b[2], b[3] or C.btnOn)
  end
  self:text(8, 1, Gui.fit(title, math.max(1, x - 10)), C.text, C.panel)
end

function Frame:editorFooter(e, what)
  self:rowBg(self.h, C.bg)
  if e.error then
    self:text(2, self.h, Gui.fit(e.error, self.w - 2), C.bad)
  else
    self:text(2, self.h, Gui.fit(("Only %s %s. Closes in %ds without a tap."):format(
      tostring(e.player or "?"), what or "can change this", e.closesIn or 0), self.w - 2), C.dim)
  end
end

return frame
