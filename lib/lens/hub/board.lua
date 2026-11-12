--[[ lens.hub.board: what's edited on the screen, kept in /home/lens-board.cfg, which only the hub writes.
  Views (a label, a query, how it reads), the dashboard's panels (views, in order) and each player's HUD.
  lens-hub.cfg stays the starting point: its panels and HUD views are in the library too, and a view edited on
  the screen overrides the one of the same label from lens-hub.cfg.

  local b = require("lens.hub.board").new(path, cfg, legacyHudPath?)
    path: the board file (nil: kept in memory only); cfg: lens.hub.config output.
    First run (no file): the dashboard gets lens-hub.cfg's panels; players' HUDs come from legacyHudPath
    (lens-hud.cfg, the first per-player file) when it's there.
    Later, a panel added to lens-hub.cfg (say by lens-setup) is put on the dashboard once; one removed on the
    screen stays removed.
  b:views() -> { view... }       the library: lens-hub.cfg's (panels, then HUD elements) with screen edits
                                 over them, then views made on the screen. Each has source = "config" |
                                 "edited" (a config view changed here) | "screen"
  b:view(label) -> view | nil
  b:panels() -> { view... }      the dashboard, in order (labels whose view is gone are skipped)
  b:onDashboard(label) -> bool
  b:setView(view, old?) -> true | nil, err    add or replace (old: the label it had, to rename: panels and HUD
                                 elements follow). Checked like a panel in lens-hub.cfg. Saved.
  b:deleteView(label) -> true | nil, err      a screen view goes; an edited one goes back to lens-hub.cfg's.
                                 A config view can't be deleted (take it off the dashboard instead). Saved.
  b:setPanels({ label... }) -> true | nil, err
  b:addPanel(label) -> true | nil, err        at the end of the dashboard
  b:undo() -> bool               the views and panels as they were before the last change (up to UNDO_DEPTH)
  b.canUndo
  b:players() -> { [name] = hud settings }   (lens.hub.huds' form; huds reads and writes them through:)
  b:setPlayers(players) -> true | nil, err
  board.UNDO_DEPTH
]]

local files = require("lens.files")
local config = require("lens.hub.config")

local board = {}

board.UNDO_DEPTH = 20

---------------------------------------------------------------- serializing
local function lit(v, indent)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t ~= "table" then return tostring(v) end
  indent = indent or ""
  local inner = indent .. "  "
  local parts, n = {}, #v
  for i = 1, n do parts[#parts + 1] = lit(v[i], inner) end
  local keys = {}
  for k in pairs(v) do
    if not (math.type(k) == "integer" and k >= 1 and k <= n) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local key = (type(k) == "string" and k:match("^[%a_][%w_]*$") and k ~= "for") and k or ("[" .. lit(k) .. "]")
    parts[#parts + 1] = key .. " = " .. lit(v[k], inner)
  end
  if #parts == 0 then return "{}" end
  local flat = "{ " .. table.concat(parts, ", ") .. " }"
  if #flat + #indent <= 110 then return flat end
  return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
end

local VIEW_KEYS = { "label", "value", "of", "max", "unit", "format", "color", "warnAbove", "badAbove", "warnBelow", "badBelow" }

local function copyView(v)
  local out = {}
  for _, k in ipairs(VIEW_KEYS) do out[k] = v[k] end
  return out
end

local function deep(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep(x) end
  return out
end

---------------------------------------------------------------- the board
local B = {}
B.__index = B

-- lens-hub.cfg's views: panels, then HUD elements with other labels.
local function configViews(cfg)
  local out, seen = {}, {}
  for _, p in ipairs(cfg.panels or {}) do
    if not seen[p.label] then out[#out + 1] = copyView(p); seen[p.label] = true end
  end
  if type(cfg.hud) == "table" then
    for _, b in ipairs(cfg.hud.blocks or {}) do
      for _, el in ipairs(b.elements or {}) do
        if (el.kind == "bar" or el.kind == "text") and not seen[el.label] then
          out[#out + 1] = copyView(el); seen[el.label] = true
        end
      end
    end
  end
  return out
end

function board.new(path, cfg, legacyHudPath)
  local self = setmetatable({ path = path, base = configViews(cfg), undoStack = {}, canUndo = false }, B)
  local saved = path and files.loadTable(path)
  local data = type(saved) == "table" and saved or {}
  self.own = {}
  for _, v in ipairs(type(data.views) == "table" and data.views or {}) do
    if type(v) == "table" and not config.checkView(copyView(v)) then self.own[#self.own + 1] = copyView(v) end
  end
  local cfgPanels = {}
  for _, p in ipairs(cfg.panels or {}) do cfgPanels[#cfgPanels + 1] = p.label end
  local changed = false
  if type(data.panels) == "table" then
    self.list = {}
    for _, l in ipairs(data.panels) do if type(l) == "string" then self.list[#self.list + 1] = l end end
    self.seen = {}
    for _, l in ipairs(type(data.seen) == "table" and data.seen or {}) do self.seen[l] = true end
    for _, l in ipairs(cfgPanels) do
      if not self.seen[l] then self.list[#self.list + 1] = l; self.seen[l] = true; changed = true end
    end
  else
    self.list, self.seen = {}, {}
    for _, l in ipairs(cfgPanels) do self.list[#self.list + 1] = l; self.seen[l] = true end
  end
  if type(data.huds) == "table" then
    self.huds = data.huds
  else
    local legacy = legacyHudPath and files.loadTable(legacyHudPath)
    self.huds = type(legacy) == "table" and legacy or {}
    changed = changed or (type(legacy) == "table" and next(legacy) ~= nil)
  end
  if changed and path and saved then self:save() end
  return self
end

function B:save()
  if not self.path then return true end
  local seen = {}
  for l in pairs(self.seen) do seen[#seen + 1] = l end
  table.sort(seen)
  local text = table.concat({
    "-- lens-board.cfg: what's edited on lens-hub's screen. Written by lens-hub; edit lens-hub.cfg instead.",
    "-- views: made or changed on the screen (one with a lens-hub.cfg label replaces that one).",
    "-- panels: the dashboard, in order. seen: lens-hub.cfg panels already offered. huds: each player's HUD.",
    "return " .. lit({ views = self.own, panels = self.list, seen = seen, huds = self.huds }),
  }, "\n") .. "\n"
  local ok, err = files.writeAtomic(self.path, text)
  if not ok then return nil, err end
  return true
end

function B:views()
  local out, mine = {}, {}
  for _, v in ipairs(self.own) do mine[v.label] = v end
  local inBase = {}
  for _, v in ipairs(self.base) do
    inBase[v.label] = true
    local view = copyView(mine[v.label] or v)
    view.source = mine[v.label] and "edited" or "config"
    out[#out + 1] = view
  end
  for _, v in ipairs(self.own) do
    if not inBase[v.label] then
      local view = copyView(v)
      view.source = "screen"
      out[#out + 1] = view
    end
  end
  return out
end

function B:view(label)
  for _, v in ipairs(self:views()) do if v.label == label then return v end end
end

function B:panels()
  local by = {}
  for _, v in ipairs(self:views()) do by[v.label] = v end
  local out = {}
  for _, l in ipairs(self.list) do if by[l] then out[#out + 1] = by[l] end end
  return out
end

function B:onDashboard(label)
  for _, l in ipairs(self.list) do if l == label then return true end end
  return false
end

function B:snapshot()
  table.insert(self.undoStack, { own = deep(self.own), list = deep(self.list) })
  while #self.undoStack > board.UNDO_DEPTH do table.remove(self.undoStack, 1) end
  self.canUndo = true
end

function B:undo()
  local s = table.remove(self.undoStack)
  if not s then return false end
  self.own, self.list = s.own, s.list
  self.canUndo = #self.undoStack > 0
  self:save()
  return true
end

-- Renames inside players' HUDs.
local function renameInHuds(huds, old, new)
  for _, s in pairs(huds) do
    for _, b in ipairs(type(s) == "table" and type(s.blocks) == "table" and s.blocks or {}) do
      local keep = {}
      for _, el in ipairs(type(b.elements) == "table" and b.elements or {}) do
        if el.view == old then
          if new then el.view = new; keep[#keep + 1] = el end
        else
          keep[#keep + 1] = el
        end
      end
      b.elements = keep
    end
  end
end

function B:setView(view, old)
  local v = copyView(view)
  local err = config.checkView(v)
  if err then return nil, err end
  old = old or v.label
  if v.label ~= old and self:view(v.label) then return nil, "there's already a view called " .. v.label end
  local wasBase = false
  for _, b in ipairs(self.base) do if b.label == old then wasBase = true end end
  if v.label ~= old and wasBase then return nil, "views from lens-hub.cfg keep their label (rename it there)" end
  self:snapshot()
  local replaced = false
  for i, o in ipairs(self.own) do
    if o.label == old then self.own[i] = v; replaced = true end
  end
  if not replaced then self.own[#self.own + 1] = v end
  if v.label ~= old then
    for i, l in ipairs(self.list) do if l == old then self.list[i] = v.label end end
    renameInHuds(self.huds, old, v.label)
  end
  return self:save()
end

function B:deleteView(label)
  local idx
  for i, o in ipairs(self.own) do if o.label == label then idx = i end end
  local wasBase = false
  for _, b in ipairs(self.base) do if b.label == label then wasBase = true end end
  if not idx then
    if wasBase then return nil, "views from lens-hub.cfg stay; take it off the dashboard instead" end
    return nil, "no view called " .. tostring(label)
  end
  self:snapshot()
  table.remove(self.own, idx)
  if not wasBase then
    local keep = {}
    for _, l in ipairs(self.list) do if l ~= label then keep[#keep + 1] = l end end
    self.list = keep
    renameInHuds(self.huds, label, nil)
  end
  return self:save()
end

function B:setPanels(list)
  self:snapshot()
  self.list = {}
  for _, l in ipairs(list) do self.list[#self.list + 1] = l end
  return self:save()
end

function B:addPanel(label)
  local list = { table.unpack(self.list) }
  list[#list + 1] = label
  return self:setPanels(list)
end

function B:players() return self.huds end

function B:setPlayers(players)
  self.huds = players
  return self:save()
end

return board
