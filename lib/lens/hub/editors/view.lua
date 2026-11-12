--[[ lens.hub.editors.view: the view editor: one view of the library (lens.hub.board), typed into with the
  keyboard (lens.hub.viewdraft), its value previewed. Opened from the EDIT and DATA pages; drawn by
  lens.hub.pages.view. The editor interface: lens.hub.editors.hud.

  E.start(app, player, v?, back, addTo?)   open it: v, a library view to change (addTo nil), or the fields of
                         a new view (addTo = "dash": put it on the dashboard; "hud": in the player's HUD).
                         back: the editor state to return to on SAVE or CANCEL.
  State: { kind = "view", player, draft, old = label | nil (new), source, back, addTo }
  Actions: viewFocus(key), viewCycle(key), viewSave, viewCancel, viewDelete. Keys and pastes type.
]]

local format = require("lens.hub.format")
local query = require("lens.hub.query")
local viewdraft = require("lens.hub.viewdraft")

local E = {}

function E.start(app, player, v, back, addTo)
  local existing = v and not addTo
  app:switch(player, { kind = "view", draft = viewdraft.draft(v), old = existing and v.label or nil,
    source = existing and v.source or nil, back = back, addTo = addTo })
end

local function back(app, player)
  app:switch(player, app.editing.back or { kind = "edit" })
end

-- The draft's value as it would show, or why it can't. Compiled fresh, not cached: every keystroke is a new
-- query.
local function preview(app, d, now)
  local v, err = viewdraft.view(d)
  if not v then return { error = err } end
  local lookup = app.hub:lookup(now)
  local value = query.compile(v.value)(lookup)
  local total = v.of and query.compile(v.of)(lookup) or nil
  local text, frac, level = format.view(v, value, total)
  return { text = text, frac = frac, level = level }
end

function E.actions(app, a, mine)
  a.viewFocus = mine(function(_, key) viewdraft.focus(app.editing.draft, key) end)
  a.viewCycle = mine(function(_, key) viewdraft.cycle(app.editing.draft, key) end)
  a.viewCancel = mine(function(player) back(app, player) end)
  a.viewSave = mine(function(player)
    local e = app.editing
    local v, err = viewdraft.view(e.draft)
    if not v then return nil, err end
    local ok, why = app.board:setView(v, e.old)
    if not ok then return nil, why end
    if not e.old and e.addTo == "dash" then
      app.board:addPanel(v.label)
    elseif not e.old and e.addTo == "hud" and app.huds then
      app.huds:change(player, function(s)
        local els = s.blocks[1].elements
        els[#els + 1] = { kind = "text", view = v.label }
      end)
    end
    back(app, player)
  end)
  a.viewDelete = mine(function(player)
    local ok, why = app.board:deleteView(app.editing.old)
    if not ok then return nil, why end
    back(app, player)
  end)
end

function E.model(app, e, now)
  local fields = {}
  for _, f in ipairs(viewdraft.FIELDS) do
    fields[#fields + 1] = { key = f.key, name = f.name, kind = f.kind, text = e.draft.fields[f.key] }
  end
  return { old = e.old, source = e.source, fields = fields, focus = e.draft.focus, preview = preview(app, e.draft, now),
    keyboard = app.env.keyboard ~= false }
end

function E.key(_, e, char, code) viewdraft.key(e.draft, char, code) end
function E.paste(_, e, text) viewdraft.paste(e.draft, text) end

return E
