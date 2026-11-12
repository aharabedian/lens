--[[ lens.hub.editors.view: the view editor: one view of the library (lens.hub.board), typed into with the
  keyboard (lens.hub.viewdraft), its value previewed. Opened from the EDIT and DATA pages; drawn by
  lens.hub.pages.view. The editor interface: lens.hub.editors.hud.

  E.start(app, player, v?, back, addTo?)   open it: v, a library view to change (addTo nil), or the fields of
                         a new view (addTo = "dash": put it on the dashboard; "hud": in the player's HUD).
                         back: the editor state to return to on SAVE or CANCEL.
  State: { kind = "view", player, draft, old = label | nil (new), source, back, addTo }
  Actions: viewFocus(focus, position?) (a field key, "rule:<i>" or "state:<i>"), viewCycle(key), viewSave,
  viewCancel, viewDelete; status rules: viewRuleAdd, viewRuleLevel(i), viewRuleMove(i, -1 | 1), viewRuleRemove(i);
  dot states: viewStateAdd, viewStateLevel(i), viewStateRemove(i). Keys and pastes type at the cursor.
]]

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

-- The draft's value as it would show (lens.hub.app's evaluateWith), or why it can't. Compiled fresh, not
-- cached: every keystroke is a new query.
local function preview(app, d, now)
  local v, err = viewdraft.view(d)
  if not v then return { error = err } end
  local lookup = app.hub:lookup(now)
  return app.evaluateWith(v, function(text) return query.compile(text)(lookup) end,
    function(text) return query.select(text)(lookup) end)
end

function E.actions(app, a, mine)
  local function draft(fn) return mine(function(_, ...) fn(app.editing.draft, ...) end) end
  a.viewFocus = draft(viewdraft.focus)
  a.viewCycle = draft(viewdraft.cycle)
  a.viewRuleAdd = draft(viewdraft.addRule)
  a.viewRuleLevel = draft(viewdraft.ruleLevel)
  a.viewRuleMove = draft(viewdraft.moveRule)
  a.viewRuleRemove = draft(viewdraft.removeRule)
  a.viewStateAdd = draft(viewdraft.addState)
  a.viewStateLevel = draft(viewdraft.stateLevel)
  a.viewStateRemove = draft(viewdraft.removeState)
  a.viewCancel = mine(function(player) back(app, player) end)
  a.viewSave = mine(function(player)
    local e = app.editing
    local v, err = viewdraft.view(e.draft)
    if not v then return nil, err end
    local ok, why = app.board:setView(v, e.old)
    if not ok then return nil, why end
    if not e.old and e.addTo == "dash" then
      app.board:addPanel(v.label, e.back and e.back.page or app.page)
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
  local d = e.draft
  local fields = {}
  for _, f in ipairs(viewdraft.FIELDS) do
    local fd = { key = f.key, name = f.name, kind = f.kind }
    if f.kind == "choice" then
      fd.text = d.choices[f.key]
    elseif f.kind == "status" then
      fd.rows = {}
      for i, r in ipairs(d.rules) do fd.rows[i] = { focus = "rule:" .. i, level = r[1], text = r[2] } end
    elseif f.kind == "states" then
      fd.rows = {}
      for i, st in ipairs(d.states) do fd.rows[i] = { focus = "state:" .. i, level = st[2], text = st[1] } end
    else
      fd.text = d.fields[f.key]
    end
    fields[#fields + 1] = fd
  end
  return { old = e.old, source = e.source, fields = fields, focus = d.focus, cursor = d.cursor,
    preview = preview(app, d, now), keyboard = app.env.keyboard ~= false }
end

function E.key(_, e, char, code) viewdraft.key(e.draft, char, code) end
function E.paste(_, e, text) viewdraft.paste(e.draft, text) end

return E
