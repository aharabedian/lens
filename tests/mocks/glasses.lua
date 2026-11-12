--[[ tests/mocks/glasses.lua - OC Glasses' Glasses Terminal (component "glasses"), as lens-discover saw it in
  game (2026-11-12): add*() take no arguments and return a widget table whose methods are fields; every widget
  has getID, set/getColor, set/getAlpha, set/isVisible; text and items set/getPosition, Scale, Rotation;
  text set/getText; rects set/getSize; quads and triangles setVertex / getVertexCount.
  Units seen in game (lens-discover --glasses-test, 2026-11-12): colors 0..1 (above 1 clamps); positions in
  GUI pixels from the top left; Rect2D setSize(a, b) makes it b wide and a tall (height first), so the mock
  stores w = b, h = a. Text is about 10 px a character and 14 px a line at scale 1; whether setScale changes
  that isn't known, so the mock just records it.

  local G = require("glasses").new()
  G.proxy                          the component (add to M.components with type "glasses")
  G.widgets[id] = widget state     { kind, id, text, x, y, w, h, color = { r, g, b }, alpha, scale, visible, removed }
  G.calls                          every call into the terminal and its widgets
  G.live() -> widget states not removed, in creation order
  G.find(text) -> the live text widget whose text contains `text`
]]

local glasses = {}

function glasses.new()
  local G = { widgets = {}, order = {}, calls = 0, nextId = 0 }
  local function count() G.calls = G.calls + 1 end

  local function widget(kind, extra)
    G.nextId = G.nextId + 1
    local s = { kind = kind, id = G.nextId - 1, visible = true, alpha = 1, scale = 1, x = 0, y = 0, w = 0, h = 0,
      color = { 1, 1, 1 } }
    G.widgets[s.id] = s
    G.order[#G.order + 1] = s
    local w = {
      getID = function() count(); return s.id end,
      setColor = function(r, g, b) count(); s.color = { r, g, b } end,
      getColor = function() count(); return table.unpack(s.color) end,
      setAlpha = function(a) count(); s.alpha = a end,
      getAlpha = function() count(); return s.alpha end,
      setVisible = function(v) count(); s.visible = v end,
      isVisible = function() count(); return s.visible end,
    }
    for _, k in ipairs(extra) do
      if k == "position" then
        w.setPosition = function(x, y) count(); s.x, s.y = x, y end
        w.getPosition = function() count(); return s.x, s.y end
      elseif k == "scale" then
        w.setScale = function(v) count(); s.scale = v end
        w.getScale = function() count(); return s.scale end
      elseif k == "text" then
        w.setText = function(t) count(); s.text = t end
        w.getText = function() count(); return s.text end
      elseif k == "size" then
        w.setSize = function(a, b) count(); s.h, s.w = a, b end        -- height first, as in game
        w.getSize = function() count(); return s.h, s.w end
      end
    end
    return w
  end

  G.proxy = {
    type = "glasses",
    addTextLabel = function() count(); return widget("text", { "position", "scale", "text" }) end,
    addRect = function() count(); return widget("rect", { "position", "size" }) end,
    getObjectCount = function()
      count()
      local n = 0
      for _, s in pairs(G.widgets) do if not s.removed then n = n + 1 end end
      return n
    end,
    removeObject = function(id)
      count()
      local s = G.widgets[id]
      if not s or s.removed then return false end
      s.removed = true
      return true
    end,
    removeAll = function() count(); for _, s in pairs(G.widgets) do s.removed = true end end,
    getBindPlayers = function() count(); return "Aaron" end,
  }

  function G.live()
    local out = {}
    for _, s in ipairs(G.order) do if not s.removed then out[#out + 1] = s end end
    return out
  end
  function G.find(text)
    for _, s in ipairs(G.order) do
      if not s.removed and s.kind == "text" and s.visible and s.text and s.text:find(text, 1, true) then return s end
    end
  end
  return G
end

return glasses
