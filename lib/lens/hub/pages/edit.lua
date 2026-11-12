--[[ lens.hub.pages.edit: the EDIT page (lens.hub.editors.edit): the dashboard's panels and the view library.

  edit.draw(f, e, actions)   e: { player, pages = { name... }, page = the one being edited, renaming = text | nil,
                             keyboard, panels = { panel... } (that page's, evaluated, in order; hidden ones
                             say so), library = { { label, source }... } (views not on that page), canUndo,
                             error, closesIn }

  Two columns at 100 columns or more, else the library below the panels.
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local edit = {}

local C = frame.C
local SOURCE = { config = "cfg", edited = "cfg*", screen = "" }

-- The pages: a tab each, + PAGE, RENAME (typed), DELETE (not the last).
local function pages(f, e, actions)
  local items = {}
  for i, name in ipairs(e.pages) do
    if e.renaming and i == e.page then
      items[#items + 1] = { e.renaming .. "▏", nil, C.sel }
    else
      items[#items + 1] = { name, function(p) actions.editPage(p, i) end, i == e.page and C.btnOn or C.btn }
    end
  end
  if e.renaming then
    items[#items + 1] = { "OK", actions.editPageRenameOk, C.btnOn }
    items[#items + 1] = { "CANCEL", actions.editPageRenameCancel, C.line }
  else
    if #e.pages < 8 then items[#items + 1] = { "+ PAGE", actions.editPageAdd } end
    if e.keyboard then items[#items + 1] = { "RENAME", actions.editPageRename, C.line } end
    if #e.pages > 1 then items[#items + 1] = { "DELETE PAGE", actions.editPageDelete, C.line } end
  end
  f:text(2, 2, "PAGES", C.accent)
  f:chips(9, 2, f.w - 10, items)
end

local function onDashboard(f, e, actions, x, width, last)
  f:heading(x, 3, ("ON %s (%d)"):format((e.pages[e.page] or "THE DASHBOARD"):upper(), #e.panels), width)
  local y = 4
  if #e.panels == 0 then f:text(x, y, "Nothing yet: add a view from the library.", C.dim); y = y + 1 end
  local labelW = width - 32
  for i, p in ipairs(e.panels) do
    if y > last then break end
    f:text(x, y, Gui.fit(p.label, labelW), C.text)
    local text = p.hidden and "hidden" or p.text or "–"
    f:text(x + labelW + 1, y, Gui.rfit(text, 10), p.hidden and C.dim or frame.levelColor(p.level, C.text))
    local bx = x + width - 19
    local label = p.label
    f:button(bx, y, "EDIT", function(pl) actions.editView(pl, label) end)
    if i > 1 then f:button(bx + 7, y, "▲", function(pl) actions.editMove(pl, i, -1) end) end
    if i < #e.panels then f:button(bx + 11, y, "▼", function(pl) actions.editMove(pl, i, 1) end) end
    f:button(bx + 15, y, "✕", function(pl) actions.editRemove(pl, i) end, C.line)
    y = y + 1
  end
  return y
end

local function library(f, e, actions, x, y, width, last)
  f:heading(x, y, ("LIBRARY (%d)"):format(#e.library), width - 12)
  f:button(x + width - 10, y, "+ NEW", actions.editNew)
  y = y + 1
  if #e.library == 0 then f:text(x, y, Gui.fit("Every view is on the dashboard.", width), C.dim) end
  for k, v in ipairs(e.library) do
    if y > last then
      f:text(x, last + 1, ("+%d more"):format(#e.library - k + 1), C.dim)
      break
    end
    local label = v.label
    f:button(x, y, "+", function(pl) actions.editAdd(pl, label) end)
    f:text(x + 4, y, Gui.fit(label, width - 22), C.text)
    f:text(x + width - 17, y, SOURCE[v.source] or "", C.dim)
    f:button(x + width - 7, y, "EDIT", function(pl) actions.editView(pl, label) end)
    y = y + 1
  end
end

function edit.draw(f, e, actions)
  local buttons = {}
  if e.canUndo then buttons[#buttons + 1] = { "UNDO", actions.editUndo, C.line } end
  buttons[#buttons + 1] = { "DONE", actions.editDone }
  f:editorHeader("Edit the dashboard", buttons)
  pages(f, e, actions)
  local last = f.h - 2
  if f.w >= 100 then
    local width = (f.w - 6) // 2
    onDashboard(f, e, actions, 2, width, last)
    library(f, e, actions, 2 + width + 3, 3, width, last)
  else
    local y = onDashboard(f, e, actions, 2, f.w - 2, last)
    library(f, e, actions, 2, y + 1, f.w - 2, last)
  end
  f:editorFooter(e)
end

return edit
