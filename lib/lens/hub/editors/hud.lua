--[[ lens.hub.editors.hud: the HUD editor: a player's own HUD (lens.hub.huds), one block at a time. Drawn by
  lens.hub.pages.hud.

  The editor interface (every lens.hub.editors.* module; lens.hub.app runs them):
    E.actions(app, a, mine)   add the editor's actions to `a`. mine(fn) wraps fn(player, ...) so it runs only for
                              the player who opened this kind of editor; fn returning nil, err (or false, err)
                              shows err in the editor's footer. Buttons that open the editor aren't wrapped.
    E.model(app, e, now) -> t  what its page draws, from e (app.editing); app adds kind, player, error, closesIn
    E.key(app, e, char, code), E.paste(app, e, text)   optional: keys and pastes while it's open

  State (app.editing): { kind = "hud", player, block = the block being edited, step = nudge px (1, 8, 32),
                         rename = a lens.hub.textfield field | nil (the active preset's new name, being typed) }
  Actions: hud(player) opens it; hudDone, hudReset, hudBlock(i), hudBlockAdd, hudBlockRemove, hudToggle(label),
  hudKind(i), hudMove(i, -1 | 1), hudAlerts(-1 | 1), hudGap, hudRemove(i), hudAnchor(anchor), hudNudge(dx, dy),
  hudStepSize, hudWidth(-1 | 1), hudScale(-1 | 1); presets: hudPreset(name), hudPresetAdd, hudPresetDelete,
  hudRename (start typing a new name), hudRenameOk, hudRenameCancel. Keys and pastes type the name; Enter is OK.
  Changes are saved at once (huds:change).
]]

local config = require("lens.hub.config")
local huds = require("lens.hub.huds")
local textfield = require("lens.hub.textfield")

local E = {}

local STEPS = { 1, 8, 32 }

local function clamp(v, lim) return math.max(lim[1], math.min(lim[2], v)) end

function E.actions(app, a, mine)
  a.hud = function(player) app:open("hud", player, { block = 1, step = 8 }) end
  -- fn(settings, block, ...) changes the player's settings; block is the one being edited.
  local function change(fn)
    return mine(function(player, ...)
      local args = table.pack(...)
      return app.huds:change(player, function(s)
        local i = math.min(app.editing.block, #s.blocks)
        app.editing.block = i
        fn(s, s.blocks[i], table.unpack(args, 1, args.n))
      end)
    end)
  end
  a.hudDone = mine(function() app:close() end)
  a.hudReset = mine(function(player) app.editing.block = 1; return app.huds:reset(player) end)
  a.hudBlock = mine(function(_, i) app.editing.block = i end)
  a.hudStepSize = mine(function()
    local e = app.editing
    for i, v in ipairs(STEPS) do if v == e.step then e.step = STEPS[i % #STEPS + 1]; return end end
    e.step = STEPS[1]
  end)
  a.hudBlockAdd = change(function(s)
    if #s.blocks >= huds.LIMITS.blocks[2] then return end
    local x, y = config.offset("top-left")
    s.blocks[#s.blocks + 1] = { anchor = "top-left", x = x, y = y, width = 160, elements = {} }
    app.editing.block = #s.blocks
  end)
  a.hudBlockRemove = change(function(s)
    if #s.blocks <= 1 then return end
    table.remove(s.blocks, app.editing.block)
    app.editing.block = math.max(1, app.editing.block - 1)
  end)
  a.hudToggle = change(function(_, b, label)
    for i, el in ipairs(b.elements) do if el.view == label then table.remove(b.elements, i); return end end
    b.elements[#b.elements + 1] = { kind = "bar", view = label }
  end)
  a.hudKind = change(function(_, b, i)
    local el = b.elements[i]
    if el and (el.kind == "bar" or el.kind == "text") then el.kind = el.kind == "bar" and "text" or "bar" end
  end)
  a.hudMove = change(function(_, b, i, dir)
    local j = i + dir
    if b.elements[i] and b.elements[j] then b.elements[i], b.elements[j] = b.elements[j], b.elements[i] end
  end)
  a.hudAlerts = change(function(_, b, dir)
    for i, el in ipairs(b.elements) do
      if el.kind == "alerts" then
        el.count = clamp(el.count + dir, huds.LIMITS.count)
        if el.count == 0 then table.remove(b.elements, i) end
        return
      end
    end
    if dir > 0 then b.elements[#b.elements + 1] = { kind = "alerts", count = 1 } end
  end)
  a.hudGap = change(function(_, b) b.elements[#b.elements + 1] = { kind = "gap" } end)
  a.hudRemove = change(function(_, b, i) table.remove(b.elements, i) end)
  a.hudAnchor = change(function(_, b, anchor)
    b.anchor = anchor
    b.x, b.y = config.offset(anchor)
  end)
  a.hudNudge = change(function(_, b, dx, dy)
    b.x, b.y = b.x + dx * app.editing.step, b.y + dy * app.editing.step
  end)
  a.hudWidth = change(function(_, b, dir) b.width = clamp(b.width + dir * huds.LIMITS.width[3], huds.LIMITS.width) end)
  a.hudScale = change(function(s, _, dir) s.scale = clamp(s.scale + dir * huds.LIMITS.scale[3], huds.LIMITS.scale) end)

  -- Presets: each switch starts at the first block.
  local function fresh() app.editing.block, app.editing.rename = 1, nil end
  a.hudPreset = mine(function(player, name) fresh(); return app.huds:usePreset(player, name) end)
  a.hudPresetAdd = mine(function(player)
    fresh()
    local name, err = app.huds:addPreset(player)
    if not name then return nil, err end
    app.editing.rename = textfield.new(name, huds.NAME_LENGTH)
    return true
  end)
  a.hudPresetDelete = mine(function(player)
    local _, active = app.huds:presets(player)
    fresh()
    return app.huds:deletePreset(player, active)
  end)
  a.hudRename = mine(function(player)
    local _, active = app.huds:presets(player)
    app.editing.rename = textfield.new(active, huds.NAME_LENGTH)
  end)
  a.hudRenameCancel = mine(function() app.editing.rename = nil end)
  a.hudRenameOk = mine(function(player) return E.rename(app, app.editing, player) end)
end

function E.rename(app, e, player)
  local _, active = app.huds:presets(player)
  local ok, err = app.huds:renamePreset(player, active, e.rename.text)
  if ok then e.rename = nil end
  return ok, err
end

function E.key(app, e, char, code)
  if e.rename and textfield.type(e.rename, char, code) == "enter" then
    local ok, err = E.rename(app, e, e.player)
    if not ok then app.editError = err end
  end
end

function E.paste(_, e, text) if e.rename then textfield.put(e.rename, text) end end

function E.model(app, e)
  local s = app.huds:settings(e.player)
  e.block = math.min(e.block, #s.blocks)
  local b = s.blocks[e.block]
  local rows, used = {}, {}
  for i, el in ipairs(b.elements) do
    rows[#rows + 1] = { index = i, kind = el.kind, label = el.view, count = el.count }
    if el.view then used[el.view] = true end
  end
  local hidden = {}
  for _, v in ipairs(app.huds:catalog(app.board:views())) do
    if not used[v.label] then hidden[#hidden + 1] = v.label end
  end
  local presets, active = app.huds:presets(e.player)
  return { own = s.own, scale = s.scale, blocks = #s.blocks, block = e.block, anchor = b.anchor, x = b.x, y = b.y,
    width = b.width, rows = rows, hidden = hidden, step = e.step, wearing = app.huds:wearing(e.player),
    presets = presets, preset = active, renaming = e.rename and e.rename.text, cursor = e.rename and e.rename.cursor,
    keyboard = app.env.keyboard ~= false }
end

return E
