--[[ lens.hub.editors.rule: alerts made on the screen. A list (ALERTS on the EDIT page): the ones made here (EDIT,
  + NEW) and lens-hub.cfg's (read-only), each saying whether it's true now; and a form (lens.hub.ruledraft): text,
  query, how long it must stay true, level, and NOW: whether it's true and when it would fire. Saved in
  lens-board.cfg (lens.hub.board) and given to the hub at once. Drawn by lens.hub.pages.rule. The editor interface:
  lens.hub.editors.hud.

  E.start(app, player, rule?, back)   the form for a rule (rule.id: change that one; else a new one from rule's
                         fields, as SAVE AS ALERT on DATA and the panel page start it); back: the state to return to
  State: { kind = "rule", player, draft = nil (the list) | ruledraft, old = id | nil, back }
  Actions: rules(player) opens the list (cfg.editors); ruleNew, ruleEdit(id), ruleFocus(key, position?), ruleLevel,
           ruleSave, ruleCancel, ruleDelete, ruleDone. Keys and pastes type at the cursor.
  Model, list: { list = true, screen = { { id, level, text, when, hold, state }... }, config = { same } }
           state: "firing" | "true" | "false" | "no data"
  Model, form: { old, fields = { { key, name, text }... }, level, focus, cursor, now = { state, text }, keyboard }
]]

local query = require("lens.hub.query")
local ruledraft = require("lens.hub.ruledraft")

local E = {}

function E.start(app, player, r, back)
  app:switch(player, { kind = "rule", draft = ruledraft.draft(r), old = r and r.id or nil, back = back })
end

local function toList(app, player) app:switch(player, { kind = "rule" }) end

local function back(app, player)
  local e = app.editing
  if e.back then app:switch(player, e.back) else toList(app, player) end
end

local function refresh(app) return app.hub:setRules(app.board:allRules()) end

function E.actions(app, a, mine)
  a.rules = function(player)
    if not app:mayEdit(player) then
      app.notice = ("Only %s can make alerts."):format(table.concat(app.cfg.editors, ", "))
      return
    end
    app:open("rule", player, {})
  end
  a.ruleDone = mine(function() app:close() end)
  a.ruleNew = mine(function(player) E.start(app, player, nil, { kind = "rule" }) end)
  a.ruleEdit = mine(function(player, id)
    for _, r in ipairs(app.board:rules()) do
      if r.id == id then return E.start(app, player, r, { kind = "rule" }) end
    end
    return nil, "That alert is gone."
  end)
  a.ruleFocus = mine(function(_, key, position) ruledraft.focus(app.editing.draft, key, position) end)
  a.ruleLevel = mine(function() ruledraft.level(app.editing.draft) end)
  a.ruleCancel = mine(function(player) back(app, player) end)
  a.ruleSave = mine(function(player)
    local e = app.editing
    local r, err = ruledraft.rule(e.draft)
    if not r then return nil, err end
    local ok, why = app.board:setRule(r, e.old)
    if not ok then return nil, why end
    refresh(app)
    back(app, player)
  end)
  a.ruleDelete = mine(function(player)
    local ok, why = app.board:deleteRule(app.editing.old)
    if not ok then return nil, why end
    refresh(app)
    toList(app, player)
  end)
end

-- Whether a rule is firing, true (not yet for long enough), false, or has no data.
local function state(app, r, now)
  for _, a in ipairs(app.hub.alerts:list()) do
    if a.node == app.cfg.node and a.id == r.id then return "firing" end
  end
  local v = app.hub:query(r.when, now)
  if v == nil then return "no data" end
  return v ~= 0 and "true" or "false"
end

local function rows(app, list, now)
  local out = {}
  for _, r in ipairs(list) do
    out[#out + 1] = { id = r.id, level = r.level, text = r.text or r.id, when = r.when, hold = r["for"] or 0,
      state = state(app, r, now) }
  end
  return out
end

-- NOW on the form: the draft's query, compiled fresh (every keystroke is a new text).
local function now(app, e, t)
  local d = e.draft
  local q, err = query.compile(d.fields.when)
  if d.fields.when:match("^%s*$") then return { state = "empty", text = "Type a query that is true when something's wrong." } end
  if not q then return { state = "error", text = tostring(err) } end
  local v = q(app.hub:lookup(t))
  local hold = tonumber(d.fields["for"]) or 0
  if v == nil then return { state = "no data", text = "No data now: it doesn't fire." } end
  if v == 0 then return { state = "false", text = "False now." } end
  local since = e.old and app.hub.rules:trueSince(e.old)
  if since and t - since >= hold then return { state = "firing", text = "True now: firing." } end
  local left = since and math.max(0, hold - (t - since)) or hold
  if left <= 0 then return { state = "true", text = "True now: it fires as soon as it's saved." } end
  return { state = "true", text = ("True now: it fires if it stays true %ds more."):format(math.ceil(left)) }
end

function E.model(app, e, t)
  if not e.draft then
    return { list = true, screen = rows(app, app.board:rules(), t), config = rows(app, app.cfg.rules or {}, t) }
  end
  local d = e.draft
  local fields = {}
  for _, f in ipairs(ruledraft.FIELDS) do fields[#fields + 1] = { key = f.key, name = f.name, text = d.fields[f.key] } end
  return { old = e.old, fields = fields, level = d.level, focus = d.focus, cursor = d.cursor, now = now(app, e, t),
    keyboard = app.env.keyboard ~= false }
end

function E.key(_, e, char, code) if e.draft then ruledraft.key(e.draft, char, code) end end
function E.paste(_, e, text) if e.draft then ruledraft.paste(e.draft, text) end end

return E
