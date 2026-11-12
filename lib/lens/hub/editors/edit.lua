--[[ lens.hub.editors.edit: the EDIT page: the dashboard's panels (order, add, remove) and the view library
  (lens.hub.board). Drawn by lens.hub.pages.edit; views open in lens.hub.editors.view. The editor interface:
  lens.hub.editors.hud.

  State: { kind = "edit", player }
  Actions: edit(player) opens it (cfg.editors, when set, lists who may); editDone, editUndo, editMove(i, -1 | 1),
  editRemove(i), editAdd(label), editView(label), editNew.
]]

local view = require("lens.hub.editors.view")

local E = {}

local function labels(app)
  local out = {}
  for _, v in ipairs(app.board:panels()) do out[#out + 1] = v.label end
  return out
end

function E.actions(app, a, mine)
  a.edit = function(player)
    if not app:mayEdit(player) then
      app.notice = ("Only %s can edit the dashboard."):format(table.concat(app.cfg.editors, ", "))
      return
    end
    app:open("edit", player, {})
  end
  a.editDone = mine(function() app:close() end)
  a.editUndo = mine(function() app.board:undo() end)
  a.editMove = mine(function(_, i, dir)
    local l = labels(app)
    if not (l[i] and l[i + dir]) then return end
    l[i], l[i + dir] = l[i + dir], l[i]
    return app.board:setPanels(l)
  end)
  a.editRemove = mine(function(_, i)
    local l = labels(app)
    table.remove(l, i)
    return app.board:setPanels(l)
  end)
  a.editAdd = mine(function(_, label) return app.board:addPanel(label) end)
  a.editView = mine(function(player, label) view.start(app, player, app.board:view(label), { kind = "edit" }) end)
  a.editNew = mine(function(player) view.start(app, player, nil, { kind = "edit" }, "dash") end)
end

function E.model(app, _, now)
  local panels, on = app:panels(now), {}
  for _, p in ipairs(panels) do on[p.label] = true end
  local library = {}
  for _, v in ipairs(app.board:views()) do
    if not on[v.label] then library[#library + 1] = { label = v.label, source = v.source } end
  end
  return { panels = panels, library = library, canUndo = app.board.canUndo }
end

return E
