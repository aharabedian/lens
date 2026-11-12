--[[ lens.hub.editors.edit: the EDIT page: the dashboard's pages, one page's panels (order, add, remove) and the
  view library (lens.hub.board). Drawn by lens.hub.pages.edit; views open in lens.hub.editors.view. The editor
  interface: lens.hub.editors.hud.

  State: { kind = "edit", player, page = the page being edited (starts at the one shown), renaming = text | nil }
  Actions: edit(player) opens it (cfg.editors, when set, lists who may); editDone, editUndo, editMove(i, -1 | 1),
  editRemove(i), editAdd(label), editView(label), editNew; pages: editPage(i), editPageAdd, editPageDelete,
  editPageRename (typed; Enter or editPageRenameOk), editPageRenameCancel.
]]

local board = require("lens.hub.board")
local textfield = require("lens.hub.textfield")
local view = require("lens.hub.editors.view")

local E = {}

local function labels(app)
  local out = {}
  for _, v in ipairs(app.board:panels(app.editing.page)) do out[#out + 1] = v.label end
  return out
end

function E.actions(app, a, mine)
  a.edit = function(player)
    if not app:mayEdit(player) then
      app.notice = ("Only %s can edit the dashboard."):format(table.concat(app.cfg.editors, ", "))
      return
    end
    app:open("edit", player, { page = app.page })
  end
  a.editDone = mine(function() app:close() end)
  a.editUndo = mine(function() app.board:undo() end)
  a.editMove = mine(function(_, i, dir)
    local l = labels(app)
    if not (l[i] and l[i + dir]) then return end
    l[i], l[i + dir] = l[i + dir], l[i]
    return app.board:setPanels(l, app.editing.page)
  end)
  a.editRemove = mine(function(_, i)
    local l = labels(app)
    table.remove(l, i)
    return app.board:setPanels(l, app.editing.page)
  end)
  a.editAdd = mine(function(_, label) return app.board:addPanel(label, app.editing.page) end)
  local function back() return { kind = "edit", page = app.editing.page } end
  a.editView = mine(function(player, label) view.start(app, player, app.board:view(label), back()) end)
  a.editNew = mine(function(player) view.start(app, player, nil, back(), "dash") end)

  a.editPage = mine(function(_, i) app.editing.page, app.editing.renaming = i, nil end)
  a.editPageAdd = mine(function()
    local i, err = app.board:addPage()
    if not i then return nil, err end
    app.editing.page = i
    app.editing.renaming = app.board:pages()[i].name
    app.editing.cursor = nil
    return true
  end)
  a.editPageDelete = mine(function()
    local ok, err = app.board:deletePage(app.editing.page)
    if ok then app.editing.page = math.max(1, app.editing.page - 1) end
    return ok, err
  end)
  a.editPageRename = mine(function()
    app.editing.renaming, app.editing.cursor = app.board:pages()[app.editing.page].name, nil
  end)
  a.editPageRenameCancel = mine(function() app.editing.renaming = nil end)
  a.editPageRenameOk = mine(function() return E.rename(app, app.editing) end)
end

function E.rename(app, e)
  local ok, err = app.board:renamePage(e.page, e.renaming)
  if ok then e.renaming = nil end
  return ok, err
end

function E.key(app, e, char, code)
  if not e.renaming then return end
  local text, cursor, action = textfield.key(e.renaming, e.cursor, char, code, board.NAME_LENGTH)
  e.renaming, e.cursor = text, cursor
  if action == "enter" then
    local ok, err = E.rename(app, e)
    if not ok then app.editError = err end
  end
end

function E.paste(_, e, text)
  if e.renaming then e.renaming, e.cursor = textfield.paste(e.renaming, e.cursor, text, board.NAME_LENGTH) end
end

function E.model(app, e, now)
  local pages = app.board:pages()
  e.page = math.max(1, math.min(e.page or 1, #pages))
  local panels, on = app:evaluate(app.board:panels(e.page), app.history, now), {}
  for _, p in ipairs(panels) do on[p.label] = true end
  local library = {}
  for _, v in ipairs(app.board:views()) do
    if not on[v.label] then library[#library + 1] = { label = v.label, source = v.source } end
  end
  local names = {}
  for _, pg in ipairs(pages) do names[#names + 1] = pg.name end
  return { panels = panels, library = library, canUndo = app.board.canUndo, pages = names, page = e.page,
    renaming = e.renaming, cursor = e.cursor, keyboard = app.env.keyboard ~= false }
end

return E
