--[[ lens.hub.pages.glance: glance mode, drawn at a third of the screen's resolution (half on short screens) after
  `glance.after` minutes without a tap, so the text is three times bigger: overall health, the views picked for it
  (as the dashboard draws panels, two rows each) and the two worst alerts that aren't muted. Any tap goes back (lens.hub.app).

  glance.draw(f, m)   m: the app's model, with glance = { panels = evaluated views } (lens.hub.dashboard)
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local glance = {}

local C = frame.C
local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD" }

function glance.draw(f, m)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LENS", C.accent, C.panel)
  f:text(8, 1, " " .. (HEALTH_TEXT[m.health] or "?") .. " ", C.bg, HEALTH_COLOR[m.health] or C.dim)
  local shown = {}
  for _, a in ipairs(m.alerts or {}) do if not a.muted then shown[#shown + 1] = a end end
  local n = #shown
  local count = n == 0 and "all quiet" or ("%d alert%s"):format(n, n == 1 and "" or "s")
  local cx = 10 + Gui.len(HEALTH_TEXT[m.health] or "?") + 2
  f:text(cx, 1, Gui.fit(count, math.max(0, f.w - cx)), C.text, C.panel)

  local alertRows = math.min(2, n)
  local lastPanelRow = f.h - 2 - alertRows - (alertRows > 0 and 1 or 0)
  local y = 3
  for _, p in ipairs(m.glance.panels or {}) do
    if not p.hidden then
      if y + 1 > lastPanelRow then break end
      f:panel(p, 2, y, f.w - 2, false)
      y = y + 2
    end
  end
  y = f.h - 1 - alertRows
  for i = 1, alertRows do
    local a = shown[i]
    local tag = a.level == "bad" and " BAD " or " WARN"
    if a.acked then f:text(2, y, tag, C.dim) else f:text(2, y, tag, C.bg, a.level == "bad" and C.bad or C.warn) end
    f:text(8, y, Gui.fit(a.text, f.w - 8), a.acked and C.dim or C.text)
    y = y + 1
  end
  f:text(2, f.h, Gui.fit("Tap for the dashboard", f.w - 2), C.dim)
end

return glance
