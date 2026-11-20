--[[ lens.hub.frame: one screenful being built: text segments per row and touch targets, plus the small widgets
  every page uses. lens.hub.dashboard turns a frame into GPU calls; pages (lens.hub.pages.*) fill it.

  local frame = require("lens.hub.frame")
  local f = frame.new(w, h)
  f.w, f.h, f.rows[y] = { bg, segs = { { x, text, fg, bg }... } }, f.hits = { { x1, y1, x2, y2, fn }... }
  f:text(x, y, s, fg?, bg?)          text, cut at the right edge
  f:rowBg(y, bg)                     a row's background
  f:hit(x1, y1, x2, y2, fn)          a touch target; fn(player, x, y) runs when it's tapped (the last one made wins)
  f:button(x, y, label, fn?, bg?) -> the x after it (one column of gap)
  f:heading(x, y, text, width)
  f:chips(x, y, width, { { label, fn, bg }... }) -> the row after the last   buttons, wrapping at width
  f:stepper(x, y, label, value, minus, plus)    label, -, value, +
  f:field(x, y, width, text, cursor, focused, fn)   a text field. Focused: scrolled so the cursor shows, the
                                     cursor as an inverted cell (cursor: characters before it). Not focused:
                                     its start, cut with …. A tap calls fn(player, position): where in the text
  frame.window(length, cursor, width) -> first   the first character a focused field shows (1-based)
  frame.withCursor(text, cursor) -> text   "▏" at the cursor (nil: the end), for a chip being renamed
  f:dots(x, y, width, dots) -> columns used    state dots (lens.hub.format.dots), colored by level; "+N" when
                                             they don't all fit
  f:panel(p, x, y, width, tall?)     one evaluated view as the dashboard shows it: status dot, label and value, then
                                     state dots, a bar (with a fraction) or a rule; with tall, a sparkline of
                                     p.history under it (lens.hub.app's evaluate rows)
  frame.wrap(text, width) -> { line... }   text broken into lines at spaces (a word longer than width is cut)
  frame.spark(history, width) -> text   the last `width` values as ▁..▇, scaled between their own low and high
  f:editorHeader(title, { { label, fn, bg? }... })   an editor's top row: LENS, title, buttons on the right
  f:editorFooter(e, what?)           e.error in red, or who the editor is for and when it closes (what: the
                                     verb, default "can change this")
  frame.C                            the palette (lens.gui)
  frame.levelColor(level, default)   bad, warn, good and off as colors; anything else: default
  frame.ago(seconds) -> "45s", "12m", "2h05m"
  frame.when(t, now, tz) -> text     a moment in real seconds (lens.hub.clock) seen at `now`: "3h12m ago" without
                                     a time zone; with tz (hours from UTC): "06:40" that day, "Thu 17:42" within the
                                     week before, "12 Nov" earlier
]]

local Gui = require("lens.gui")
local unicode = require("unicode")

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

local DAYS = { "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed" }      -- 1 January 1970 was a Thursday
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- Day and month of a day number (days since 1970-01-01): Howard Hinnant's civil_from_days.
local function dayMonth(z)
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  return doy - (153 * mp + 2) // 5 + 1, mp < 10 and mp + 3 or mp - 9
end

function frame.when(t, now, tz)
  if not tz then return frame.ago(now - t) .. " ago" end
  local lt, ln = t + tz * 3600, now + tz * 3600
  local day, today = math.floor(lt / 86400), math.floor(ln / 86400)
  local s = math.floor(lt - day * 86400)
  local hm = ("%02d:%02d"):format(s // 3600, (s % 3600) // 60)
  if day == today then return hm end
  if day < today and today - day < 7 then return DAYS[day % 7 + 1] .. " " .. hm end
  local d, m = dayMonth(day)
  return ("%d %s"):format(d, MONTHS[m])
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

function frame.window(length, cursor, width)
  cursor = cursor or length
  if length + 1 <= width then return 1 end
  return math.max(1, math.min(cursor + 2 - width, length + 2 - width))   -- keep the cursor's cell in view
end

function frame.withCursor(text, cursor)
  cursor = cursor or Gui.len(text)
  return unicode.sub(text, 1, cursor) .. "▏" .. unicode.sub(text, cursor + 1)
end

function Frame:field(x, y, width, text, cursor, focused, fn)
  local n = Gui.len(text)
  local first = 1
  if focused then
    cursor = math.max(0, math.min(cursor or n, n))
    first = frame.window(n, cursor, width)
    self:text(x, y, Gui.fit(unicode.sub(text, first, first + width - 1), width), C.text, C.sel)
    local under = unicode.sub(text, cursor + 1, cursor + 1)
    self:text(x + cursor - first + 1, y, under == "" and " " or under, C.sel, C.text)
  else
    self:text(x, y, Gui.fit(text, width), C.dim, C.field)
  end
  if fn then
    self:hit(x, y, x + width - 1, y, function(player, tx)
      fn(player, math.max(0, math.min(n, first - 1 + (tx or x) - x)))
    end)
  end
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

local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇" }

function frame.wrap(text, width)
  local lines, cur = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if cur == "" then cur = word
    elseif Gui.len(cur) + 1 + Gui.len(word) <= width then cur = cur .. " " .. word
    else lines[#lines + 1] = cur; cur = word end
    while Gui.len(cur) > width do
      lines[#lines + 1] = unicode.sub(cur, 1, width)
      cur = unicode.sub(cur, width + 1)
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

-- The last `width` values of history, scaled between their own low and high.
function frame.spark(history, width)
  local n = #history
  if n == 0 then return "" end
  local first = math.max(1, n - width + 1)
  local lo, hi = math.huge, -math.huge
  for i = first, n do
    local v = history[i]
    if v then lo, hi = math.min(lo, v), math.max(hi, v) end
  end
  local out = {}
  for i = first, n do
    local v = history[i]
    if not v then
      out[#out + 1] = " "
    elseif hi == lo then
      out[#out + 1] = SPARK[1]
    else
      out[#out + 1] = SPARK[math.floor((v - lo) / (hi - lo) * (#SPARK - 1) + 0.5) + 1]
    end
  end
  return table.concat(out)
end

function Frame:panel(p, x, y, width, tall)
  local text = (p.text ~= "–" or not (p.dots or p.status)) and p.text or ""
  local lx = x
  if p.status then                                  -- the status dot leads the label
    self:text(x, y, "●", frame.levelColor(p.status, C.dim))
    lx = x + 2
  end
  self:text(lx, y, Gui.fit(p.label, width - Gui.len(text) - 1 - (lx - x)), C.dim)
  self:text(x + width - Gui.len(text), y, text, frame.levelColor(p.level, C.text))
  if p.dots then
    self:dots(x, y + 1, width, p.dots)
  elseif p.frac then
    local filled = math.floor(math.max(0, math.min(1, p.frac)) * width + 0.5)
    if filled > 0 then self:text(x, y + 1, string.rep(" ", filled), C.text, frame.levelColor(p.level, C.info)) end
    if filled < width then self:text(x + filled, y + 1, string.rep(" ", width - filled), C.text, C.line) end
  else
    self:text(x, y + 1, string.rep("─", width), C.line)
  end
  if tall then self:text(x, y + 2, frame.spark(p.history or {}, width), C.info) end
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
