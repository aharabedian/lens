--[[ lens.hub.dashboard: the hub's screen. Draws the app's model with one page, and sends the GPU only what
  changed since the last draw. Knows nothing about the network.

  local d = require("lens.hub.dashboard").new(gpu, w, h)
  d:draw(model, actions)   build a frame (lens.hub.frame) with the page for the model, then redraw only the rows
                           (or, when a row keeps its shape, the segments) that differ from the last draw
  d:tap(x, y, player?) -> bool   run the touch target under (x, y): fn(player, x, y)
  d:restore()              plain terminal colors again (on exit)

  model = {
    now, port, node, version, health = "ok" | "warn" | "bad", missingConfig = bool,
    nodes  = store:nodes(now),
    alerts = alerts:list(), counts = alerts:counts(),
    panels = { { label, text, frac = 0..1 | nil, level = "bad" | "warn" | "good" | nil, history = { number... } } },
    huds = bool,             Glasses Terminals attached: the header has a HUD button
    notice = text | nil,     shown in the footer (who has the editor, who may edit)
    hudError = text | nil,   shown in the footer
    hudPerMinute = n | nil,  HUD component calls in the last minute, shown in the footer
    pages = { name... }, page = i   the dashboard's pages and the one shown (tabs when there are several)
    logged = n               ended alerts the LOG page has
    editor = nil | { kind = "hud" | "edit" | "view" | "data" | "log", player, error, closesIn, ... }
                             an editor is open: its page (lens.hub.pages.<kind>) is drawn instead of the
                             dashboard; the rest of its fields are that page's (its header comment)
  }
  actions: what pages' touch targets call (lens.hub.app builds them; lens.hub.editors.* add the editors')
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local dashboard = {}

local PAGES = {
  main = require("lens.hub.pages.main"),
  hud  = require("lens.hub.pages.hud"),
  edit = require("lens.hub.pages.edit"),
  view = require("lens.hub.pages.view"),
  data = require("lens.hub.pages.data"),
  log  = require("lens.hub.pages.log"),
}

local function rowKey(row)
  local parts = { row.bg }
  for _, s in ipairs(row.segs) do parts[#parts + 1] = s[1] .. "\1" .. s[2] .. "\1" .. s[3] .. "\1" .. s[4] end
  return table.concat(parts, "\2")
end

-- Same background and the same segments at the same places with the same widths: only texts or colors
-- changed, so those segments can be redrawn in place.
local function sameShape(a, b)
  if not a or a.bg ~= b.bg or #a.segs ~= #b.segs then return false end
  for i, sa in ipairs(a.segs) do
    local sb = b.segs[i]
    if sa[1] ~= sb[1] or Gui.len(sa[2]) ~= Gui.len(sb[2]) then return false end
  end
  return true
end

local Dash = {}
Dash.__index = Dash

function dashboard.new(gpu, w, h)
  return setmetatable({ ui = Gui.new(gpu, w, h), w = w, h = h, last = {}, hits = {} }, Dash)
end

function Dash:build(m, actions)
  local f = frame.new(self.w, self.h)
  local e = m.editor
  if e and PAGES[e.kind] then
    PAGES[e.kind].draw(f, e, actions)
  else
    PAGES.main.draw(f, m, actions)
  end
  return f
end

function Dash:draw(m, actions)
  local f = self:build(m, actions)
  local ui = self.ui
  for y = 1, self.h do
    local row = f.rows[y]
    local key = rowKey(row)
    local last = self.last[y]
    if not last or last.key ~= key then
      if sameShape(last and last.row, row) then
        for i, sg in ipairs(row.segs) do
          local old = last.row.segs[i]
          if old[2] ~= sg[2] or old[3] ~= sg[3] or old[4] ~= sg[4] then ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
        end
      else
        ui.fill(1, y, self.w, 1, row.bg)
        for _, sg in ipairs(row.segs) do ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
      end
      self.last[y] = { key = key, row = row }
    end
  end
  self.hits = f.hits
end

function Dash:tap(x, y, player)
  for i = #self.hits, 1, -1 do
    local h = self.hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
      if h[5] then h[5](player, x, y) end
      return true
    end
  end
  return false
end

function Dash:restore() self.ui.restore() end

return dashboard
