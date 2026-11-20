--[[ lens.hub.daily: the panels' last 24 hours, one value a slot (SLOT seconds: the average of that slot's samples),
  kept across restarts in /home/lens-history.cfg (only lens-hub writes it). Times are real seconds (lens.hub.clock).
  About 2.3 KB of memory per panel. Pure apart from the file.

  local d = require("lens.hub.daily").new(path?)   path nil: memory only; what's there is read back
  d:add(label, value, time)    a sample (value nil: no data). When time reaches the next slot, the one before closes:
                               its average is kept (false when it had no data; slots the hub was off for too)
  d:values(label, time) -> { number | false... }   up to SLOTS closed slots, oldest first, the last one just before
                               the slot time is in (gaps since then count as false)
  d:keep(labels)               only these panels keep a history ({ [label] = true })
  d:save() -> true | nil, err  writes the file when a slot closed since the last save (d.dirty)
  daily.SLOT, daily.SLOTS      600, 144
]]

local files = require("lens.files")

local daily = {}

daily.SLOT = 600
daily.SLOTS = 144

local D = {}
D.__index = D

-- A panel's history: first = the slot number of values[1]; values in slot order.
local function series(first, values) return { first = first, values = values } end

function daily.new(path)
  local self = setmetatable({ path = path, panels = {}, acc = {}, dirty = false }, D)
  local saved = path and files.loadTable(path)
  if type(saved) == "table" and type(saved.panels) == "table" then
    for label, s in pairs(saved.panels) do
      if type(label) == "string" and type(s) == "table" and math.type(s.first) == "integer" and type(s.values) == "table" then
        local values = {}
        for i, v in ipairs(s.values) do values[i] = type(v) == "number" and v or false end
        self.panels[label] = series(s.first, values)
      end
    end
  end
  return self
end

local function slotOf(time) return math.floor(time / daily.SLOT) end

-- Close label's slots before `slot`: the open one's average, then false for any the hub missed.
local function closeUpTo(self, label, slot)
  local a = self.acc[label]
  local s = self.panels[label]
  if not s then
    if not a then return end
    s = series(a.slot, {})
    self.panels[label] = s
  end
  local nextSlot = s.first + #s.values
  while nextSlot < slot do
    local v = false
    if a and a.slot == nextSlot and a.n > 0 then v = a.sum / a.n end
    s.values[#s.values + 1] = v
    nextSlot = nextSlot + 1
    self.dirty = true
  end
  while #s.values > daily.SLOTS do
    table.remove(s.values, 1)
    s.first = s.first + 1
  end
end

function D:add(label, value, time)
  local slot = slotOf(time)
  local a = self.acc[label]
  if a and a.slot ~= slot then
    closeUpTo(self, label, slot)
    a = nil
  elseif not a and self.panels[label] then
    closeUpTo(self, label, slot)                 -- after a restart: the slots it missed
  end
  if not a then
    a = { slot = slot, sum = 0, n = 0 }
    self.acc[label] = a
    if not self.panels[label] then self.panels[label] = series(slot, {}) end
  end
  if type(value) == "number" then a.sum, a.n = a.sum + value, a.n + 1 end
end

function D:values(label, time)
  local s = self.panels[label]
  if not s then return {} end
  local last = slotOf(time) - 1
  local from = math.max(s.first, last - daily.SLOTS + 1)
  local out = {}
  for slot = from, last do
    local v = s.values[slot - s.first + 1]
    if v == nil then v = false end               -- the open slot, or one not closed yet
    out[#out + 1] = v
  end
  return out
end

function D:keep(labels)
  for label in pairs(self.panels) do
    if not labels[label] then self.panels[label], self.acc[label], self.dirty = nil, nil, true end
  end
end

function D:save()
  if not self.path or not self.dirty then return true end
  local out = { "-- lens-history.cfg: each panel's last 24 hours, one value per 10 minutes. Written by lens-hub.",
    "return { panels = {" }
  local labels = {}
  for label in pairs(self.panels) do labels[#labels + 1] = label end
  table.sort(labels)
  for _, label in ipairs(labels) do
    local s = self.panels[label]
    local vs = {}
    for i, v in ipairs(s.values) do vs[i] = v and ("%.6g"):format(v) or "false" end
    out[#out + 1] = ("  [%q] = { first = %d, values = { %s } },"):format(label, s.first, table.concat(vs, ", "))
  end
  out[#out + 1] = "} }"
  local ok, err = files.writeAtomic(self.path, table.concat(out, "\n") .. "\n")
  if not ok then return nil, err end
  self.dirty = false
  return true
end

return daily
