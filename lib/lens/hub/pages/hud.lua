--[[ lens.hub.pages.hud: the HUD editor (lens.hub.editors.hud): one player's blocks, a block's elements, where it
  sits.

  hud.draw(f, e, actions)   e: the editor's model: { player, presets = { name... }, preset = the active one,
                            renaming = text | nil, keyboard, own, scale, blocks = n, block = i (being edited),
                            anchor, x, y, width, step, rows = { { index, kind, label?, count? }... } (the block's
                            elements), hidden = { label... } (views that could be added), wearing = n, error,
                            closesIn }
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local hud = {}

local C = frame.C
local ARROWS = { ["top-left"] = "↖", top = "↑", ["top-right"] = "↗", left = "←", center = "•", right = "→",
  ["bottom-left"] = "↙", bottom = "↓", ["bottom-right"] = "↘" }
local GRID = { "top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right" }

-- Tabs for the player's HUDs (presets), + to copy the active one, RENAME (typed), DELETE.
local function presets(f, e, actions)
  f:text(2, 2, "HUDS", C.accent)
  local items = {}
  for _, name in ipairs(e.presets) do
    local n = name
    if e.renaming and n == e.preset then
      items[#items + 1] = { frame.withCursor(e.renaming, e.cursor), nil, C.sel }
    else
      items[#items + 1] = { n, function(p) actions.hudPreset(p, n) end, n == e.preset and C.btnOn or C.btn }
    end
  end
  if e.renaming then
    items[#items + 1] = { "OK", actions.hudRenameOk, C.btnOn }
    items[#items + 1] = { "CANCEL", actions.hudRenameCancel, C.line }
  else
    if #e.presets < 8 then items[#items + 1] = { "+", actions.hudPresetAdd } end
    if e.keyboard then items[#items + 1] = { "RENAME", actions.hudRename, C.line } end
    if #e.presets > 1 then items[#items + 1] = { "DELETE", actions.hudPresetDelete, C.line } end
  end
  f:chips(9, 2, f.w - 10, items)
end

-- Tabs for the blocks, + to add one, REMOVE for the one being edited.
local function blocks(f, e, actions)
  f:text(2, 3, "BLOCKS", C.accent)
  local bx = 9
  for i = 1, e.blocks do
    bx = f:button(bx, 3, tostring(i), function(p) actions.hudBlock(p, i) end, i == e.block and C.btnOn or C.btn)
  end
  if e.blocks < 6 then bx = f:button(bx, 3, "+", actions.hudBlockAdd) end
  if e.blocks > 1 then f:button(bx + 1, 3, "REMOVE " .. e.block, actions.hudBlockRemove, C.line) end
end

-- The block's elements in order, then the views that could be added, then + ALERTS and + GAP.
local function elements(f, e, actions, lx, lw)
  f:text(lx, 5, Gui.fit(("IN BLOCK %d"):format(e.block), lw), C.accent)
  local y, last = 6, f.h - 2
  local labelW = lw - 20
  local left = #e.rows + #e.hidden
  local function full()
    if y <= last then return false end
    f:text(lx, last + 1, ("+%d more"):format(left), C.dim)
    return true
  end
  local hasAlerts = false
  for k, r in ipairs(e.rows) do
    if full() then return end
    local i = r.index
    f:text(lx, y, "[✓]", C.good)
    if r.kind == "alerts" then
      hasAlerts = true
      f:text(lx + 4, y, Gui.fit("Alerts", labelW - 6), C.text)
      f:hit(lx, y, lx + 9, y, function(p) actions.hudRemove(p, i) end)
      f:button(lx + lw - 21, y, "-", function(p) actions.hudAlerts(p, -1) end)
      f:text(lx + lw - 17, y, tostring(r.count), C.text)
      f:button(lx + lw - 15, y, "+", function(p) actions.hudAlerts(p, 1) end)
    elseif r.kind == "gap" then
      f:text(lx + 4, y, Gui.fit("(gap)", labelW), C.dim)
      f:hit(lx, y, lx + labelW + 3, y, function(p) actions.hudRemove(p, i) end)
    else
      local label = r.label
      f:text(lx + 4, y, Gui.fit(label, labelW), C.text)
      f:hit(lx, y, lx + labelW + 3, y, function(p) actions.hudToggle(p, label) end)
      f:button(lx + lw - 15, y, r.kind == "bar" and "BAR " or "TEXT", function(p) actions.hudKind(p, i) end,
        r.kind == "bar" and C.btnOn or C.sel)
    end
    if k > 1 then f:button(lx + lw - 8, y, "▲", function(p) actions.hudMove(p, i, -1) end) end
    if k < #e.rows then f:button(lx + lw - 4, y, "▼", function(p) actions.hudMove(p, i, 1) end) end
    y, left = y + 1, left - 1
  end
  for _, label in ipairs(e.hidden) do
    if full() then return end
    f:text(lx, y, "[ ]", C.dim)
    f:text(lx + 4, y, Gui.fit(label, labelW), C.dim)
    f:hit(lx, y, lx + labelW + 3, y, function(p) actions.hudToggle(p, label) end)
    y, left = y + 1, left - 1
  end
  if y <= last then
    local ax = lx
    if not hasAlerts then ax = f:button(ax, y, "+ ALERTS", function(p) actions.hudAlerts(p, 1) end) end
    f:button(ax, y, "+ GAP", actions.hudGap)
  end
end

-- The anchor grid, nudges and the step, width, size, back to default, and whether anyone sees it.
local function position(f, e, actions, rx)
  f:text(rx, 5, "POSITION", C.accent)
  for k, a in ipairs(GRID) do
    local gx, gy = rx + ((k - 1) % 3) * 4, 6 + (k - 1) // 3
    f:button(gx, gy, ARROWS[a], function(p) actions.hudAnchor(p, a) end, e.anchor == a and C.btnOn or C.btn)
  end
  local nx = rx + 15
  f:button(nx + 4, 6, "▲", function(p) actions.hudNudge(p, 0, -1) end)
  f:button(nx, 7, "◀", function(p) actions.hudNudge(p, -1, 0) end)
  f:button(nx + 8, 7, "▶", function(p) actions.hudNudge(p, 1, 0) end)
  f:button(nx + 4, 8, "▼", function(p) actions.hudNudge(p, 0, 1) end)
  f:text(rx, 10, Gui.fit(("%s, x %d y %d"):format(e.anchor, e.x, e.y), 22), C.dim)
  f:button(rx + 23, 10, ("%dpx"):format(e.step), actions.hudStepSize, C.sel)
  f:stepper(rx, 12, "Width", tostring(e.width), function(p) actions.hudWidth(p, -1) end,
    function(p) actions.hudWidth(p, 1) end)
  f:stepper(rx, 13, "Size", ("%.2g"):format(e.scale), function(p) actions.hudScale(p, -1) end,
    function(p) actions.hudScale(p, 1) end)
  if e.own then f:button(rx, 15, "BACK TO DEFAULT", actions.hudReset, C.line) end
  local note
  if e.wearing == 0 then
    note = { "No terminal shows this HUD yet:", "link your glasses to one", "of your own." }
  else
    note = { ("Showing on %d terminal%s."):format(e.wearing, e.wearing == 1 and "" or "s"), "Changes apply at once." }
  end
  for i, l in ipairs(note) do f:text(rx, 16 + i, Gui.fit(l, f.w - rx), e.wearing == 0 and C.warn or C.dim) end
end

function hud.draw(f, e, actions)
  f:editorHeader("HUD for " .. tostring(e.player or "?"), { { "DONE", actions.hudDone } })
  presets(f, e, actions)
  blocks(f, e, actions)
  local lw = math.min(46, f.w - 36)
  elements(f, e, actions, 2, lw)
  position(f, e, actions, 2 + lw + 4)
  f:editorFooter(e)
end

return hud
