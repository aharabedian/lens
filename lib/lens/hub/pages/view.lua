--[[ lens.hub.pages.view: the view editor (lens.hub.editors.view): one view's fields, typed or cycled, and its
  value as it would show.

  view.draw(f, e, actions)   e: { player, old = label | nil (a new view), source = "config" | "edited" | "screen"
                             | nil, fields = { { key, name, kind = "text" | "number" | "choice", text }... },
                             focus = key, preview = { text, frac, level, dots?, hidden? } | { error }, keyboard = bool, error,
                             closesIn }
]]

local Gui = require("lens.gui")
local unicode = require("unicode")
local frame = require("lens.hub.frame")

local view = {}

local C = frame.C

local function fields(f, e, actions, nx, fx, fw)
  local y = 3
  for _, fd in ipairs(e.fields) do
    local key = fd.key
    f:text(nx, y, Gui.fit(fd.name, fx - nx - 1), C.dim)
    if fd.kind == "choice" then
      f:button(fx, y, Gui.fit(fd.text, 10), function(pl) actions.viewCycle(pl, key) end, C.sel)
    else
      local focused = e.focus == key
      local shown = fd.text .. (focused and "▏" or "")
      if Gui.len(shown) > fw then shown = "…" .. unicode.sub(shown, -(fw - 1)) end   -- the end, where you type
      f:text(fx, y, Gui.fit(shown, fw), focused and C.text or C.dim, focused and C.sel or C.field)
      f:hit(fx, y, fx + fw - 1, y, function(pl) actions.viewFocus(pl, key) end)
    end
    y = y + 1
  end
  return y
end

local function preview(f, pv, y, nx, fx, fw)
  f:text(nx, y, "Now", C.accent)
  if pv.error then
    f:text(fx, y, Gui.fit(pv.error, fw), C.bad)
    return
  end
  local color = frame.levelColor(pv.level, C.text)
  local text = (pv.dots and pv.text == "–") and "" or pv.text or "–"   -- dots alone: no "–" before them
  f:text(fx, y, Gui.fit(text, 16), color)
  if pv.hidden then f:text(fx + 17, y, "(hidden now: Show when is false)", C.dim); return end
  if pv.dots then
    f:dots(fx + 18, y, math.max(0, fw - 18), pv.dots)
  elseif pv.frac then
    local bw = math.max(0, fw - 18)
    local filled = math.floor(math.max(0, math.min(1, pv.frac)) * bw + 0.5)
    if filled > 0 then f:text(fx + 18, y, string.rep(" ", filled), C.text, frame.levelColor(pv.level, C.info)) end
    if filled < bw then f:text(fx + 18 + filled, y, string.rep(" ", bw - filled), C.text, C.line) end
  end
end

function view.draw(f, e, actions)
  f:editorHeader(e.old and ("View: " .. e.old) or "New view",
    { { "SAVE", actions.viewSave }, { "CANCEL", actions.viewCancel, C.line } })
  local nx, fx = 2, 15
  local fw = f.w - fx - 1
  local gap = f.h >= 30 and 1 or 0                    -- spacer rows only when there's room (tier 2 has 25)
  local y = fields(f, e, actions, nx, fx, fw) + gap
  preview(f, e.preview or {}, y, nx, fx, fw)
  y = y + 1 + gap
  if e.keyboard then
    f:text(nx, y, Gui.fit("Tap a field and type. Enter: the next field. Insert pastes your clipboard.", f.w - 2), C.dim)
  else
    f:text(nx, y, Gui.fit("No keyboard on this screen: attach one to type into the fields.", f.w - 2), C.warn)
  end
  y = y + 1
  if e.source == "config" or e.source == "edited" then
    f:text(nx, y, Gui.fit("From lens-hub.cfg: your changes are kept on the screen's side.", f.w - 2), C.dim)
    y = y + 1
  end
  if e.old and e.source ~= "config" then
    f:button(nx, y + gap, e.source == "edited" and "BACK TO lens-hub.cfg" or "DELETE VIEW", actions.viewDelete, C.line)
  end
  f:editorFooter(e)
end

return view
