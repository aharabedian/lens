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
  Pages: the dashboard is one or more named pages of panels (a board from 0.2.0 has one, "Main"). `page` is an
  index, default 1; new lens-hub.cfg panels go on the first page.
  b:pages() -> { { name, count }... }
  b:panels(page?) -> { view... } a page's panels, in order (labels whose view is gone are skipped)
  b:allPanels() -> { view... }   every page's, each once
  b:onDashboard(label, page?) -> bool        on that page, or on any page
  b:addPage(name?) -> index | nil, err        "Page 2", ... when no name; at most MAX_PAGES
  b:renamePage(page, name) -> true | nil, err
  b:deletePage(page) -> true | nil, err      not the last; its panels leave the dashboard (views stay)
  b:setView(view, old?) -> true | nil, err    add or replace (old: the label it had, to rename: panels and HUD
                                 elements follow). Checked like a panel in lens-hub.cfg. Saved.
  b:deleteView(label) -> true | nil, err      a screen view goes; an edited one goes back to lens-hub.cfg's.
                                 A config view can't be deleted (take it off the dashboard instead). Saved.
  b:setPanels({ label... }, page?) -> true | nil, err
  b:addPanel(label, page?) -> true | nil, err  at the end of the page
  b:undo() -> bool               the views and pages as they were before the last change (up to UNDO_DEPTH)
  b.canUndo
  b:players() -> { [name] = hud settings }   (lens.hub.huds' form; huds reads and writes them through:)
  b:setPlayers(players) -> true | nil, err
  board.UNDO_DEPTH
]]

local files = require("lens.files")
local config = require("lens.hub.config")

local board = {}

board.UNDO_DEPTH = 20
board.MAX_PAGES = 8
board.NAME_LENGTH = 16

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

local VIEW_KEYS = { "label", "value", "of", "max", "unit", "format", "color", "warnAbove", "badAbove", "warnBelow",
  "badBelow", "text", "values", "dots", "by", "idle", "when" }

local function copyView(v)
  local out = {}
  for _, k in ipairs(VIEW_KEYS) do
    local x = v[k]
    if type(x) == "table" then
      local t = {}
      for a, b in pairs(x) do t[a] = b end
      x = t
    end
    out[k] = x
  end
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
  local function labels(t)
    local out = {}
    for _, l in ipairs(type(t) == "table" and t or {}) do if type(l) == "string" then out[#out + 1] = l end end
    return out
  end
  self.pagelist, self.seen = {}, {}
  if type(data.pages) == "table" then
    for _, pg in ipairs(data.pages) do
      if type(pg) == "table" and type(pg.name) == "string" and #self.pagelist < board.MAX_PAGES then
        self.pagelist[#self.pagelist + 1] = { name = pg.name, list = labels(pg.panels) }
      end
    end
  elseif type(data.panels) == "table" then           -- 0.2.0: one list of panels
    self.pagelist[1] = { name = "Main", list = labels(data.panels) }
  end
  if #self.pagelist == 0 then
    self.pagelist[1] = { name = "Main", list = {} }
    for _, l in ipairs(cfgPanels) do self.pagelist[1].list[#self.pagelist[1].list + 1] = l; self.seen[l] = true end
  else
    for _, l in ipairs(labels(data.seen)) do self.seen[l] = true end
    for _, l in ipairs(cfgPanels) do
      if not self.seen[l] then
        local list = self.pagelist[1].list
        list[#list + 1] = l
        self.seen[l] = true
        changed = true
      end
    end
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
    "-- pages: the dashboard's pages and their panels, in order. seen: lens-hub.cfg panels already offered.",
    "-- huds: each player's HUDs.",
    "return " .. lit({ views = self.own, pages = self:storedPages(), seen = seen, huds = self.huds }),
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

function B:storedPages()
  local out = {}
  for _, pg in ipairs(self.pagelist) do out[#out + 1] = { name = pg.name, panels = pg.list } end
  return out
end

local function pageOf(self, page) return self.pagelist[page or 1] or self.pagelist[1] end

function B:pages()
  local out = {}
  for _, pg in ipairs(self.pagelist) do out[#out + 1] = { name = pg.name, count = #pg.list } end
  return out
end

function B:panels(page)
  local by = {}
  for _, v in ipairs(self:views()) do by[v.label] = v end
  local out = {}
  for _, l in ipairs(pageOf(self, page).list) do if by[l] then out[#out + 1] = by[l] end end
  return out
end

function B:allPanels()
  local out, seen = {}, {}
  for i = 1, #self.pagelist do
    for _, v in ipairs(self:panels(i)) do
      if not seen[v.label] then out[#out + 1] = v; seen[v.label] = true end
    end
  end
  return out
end

function B:onDashboard(label, page)
  for i, pg in ipairs(self.pagelist) do
    if page == nil or page == i then
      for _, l in ipairs(pg.list) do if l == label then return true end end
    end
  end
  return false
end

local function cleanName(name)
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then return nil, "a page needs a name" end
  if #name > board.NAME_LENGTH then return nil, ("names are at most %d characters"):format(board.NAME_LENGTH) end
  return name
end

function B:addPage(name)
  if #self.pagelist >= board.MAX_PAGES then return nil, ("at most %d pages"):format(board.MAX_PAGES) end
  if name then
    local err
    name, err = cleanName(name)
    if not name then return nil, err end
  else
    local n = #self.pagelist + 1
    local taken = {}
    for _, pg in ipairs(self.pagelist) do taken[pg.name] = true end
    while taken["Page " .. n] do n = n + 1 end
    name = "Page " .. n
  end
  self:snapshot()
  self.pagelist[#self.pagelist + 1] = { name = name, list = {} }
  local ok, err = self:save()
  if not ok then return nil, err end
  return #self.pagelist
end

function B:renamePage(page, name)
  local pg = self.pagelist[page]
  if not pg then return nil, "no such page" end
  local clean, err = cleanName(name)
  if not clean then return nil, err end
  self:snapshot()
  pg.name = clean
  return self:save()
end

function B:deletePage(page)
  if not self.pagelist[page] then return nil, "no such page" end
  if #self.pagelist == 1 then return nil, "the last page stays" end
  self:snapshot()
  table.remove(self.pagelist, page)
  return self:save()
end

function B:snapshot()
  table.insert(self.undoStack, { own = deep(self.own), pagelist = deep(self.pagelist) })
  while #self.undoStack > board.UNDO_DEPTH do table.remove(self.undoStack, 1) end
  self.canUndo = true
end

function B:undo()
  local s = table.remove(self.undoStack)
  if not s then return false end
  self.own, self.pagelist = s.own, s.pagelist
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
    for _, pg in ipairs(self.pagelist) do
      for i, l in ipairs(pg.list) do if l == old then pg.list[i] = v.label end end
    end
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
    for _, pg in ipairs(self.pagelist) do
      local keep = {}
      for _, l in ipairs(pg.list) do if l ~= label then keep[#keep + 1] = l end end
      pg.list = keep
    end
    renameInHuds(self.huds, label, nil)
  end
  return self:save()
end

function B:setPanels(list, page)
  self:snapshot()
  local pg = pageOf(self, page)
  pg.list = {}
  for _, l in ipairs(list) do pg.list[#pg.list + 1] = l end
  return self:save()
end

function B:addPanel(label, page)
  local list = { table.unpack(pageOf(self, page).list) }
  list[#list + 1] = label
  return self:setPanels(list, page)
end

function B:players() return self.huds end

function B:setPlayers(players)
  self.huds = players
  return self:save()
end

return board
