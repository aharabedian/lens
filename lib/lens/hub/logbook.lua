--[[ lens.hub.logbook: the alert log, kept across restarts in /home/lens-log.cfg (only lens-hub writes it).
  Times are real seconds since 1970 (lens.hub.clock), so entries from before a restart keep their dates.

  local L = require("lens.hub.logbook").new(path, keep?)
    path: the file (nil: kept in memory only); what's there is read back. keep: entries kept (KEEP), oldest dropped
  L:add(entry)        newest first. entry = { kind, at, ... }:
      "alert": an alert that ended: node, id, level (the worst it reached), text, since (when it started), at
               (when it ended), ackedBy (who acknowledged it, if anyone did)
      "start" | "stop": lens-hub started or stopped, at
  L:list() -> { entry... }   newest first (a new list; the entries are the log's own)
  L.count
  L:save() -> true | nil, err   writes the file when something was added since the last save (L.dirty)
  logbook.KEEP
]]

local files = require("lens.files")

local logbook = {}

logbook.KEEP = 300

local L = {}
L.__index = L

local function valid(e)
  return type(e) == "table" and type(e.kind) == "string" and type(e.at) == "number"
end

function logbook.new(path, keep)
  local self = setmetatable({ path = path, keep = keep or logbook.KEEP, entries = {}, count = 0, dirty = false }, L)
  local saved = path and files.loadTable(path)
  if type(saved) == "table" and type(saved.entries) == "table" then
    for _, e in ipairs(saved.entries) do
      if valid(e) and #self.entries < self.keep then self.entries[#self.entries + 1] = e end
    end
  end
  self.count = #self.entries
  return self
end

function L:add(entry)
  table.insert(self.entries, 1, entry)
  while #self.entries > self.keep do table.remove(self.entries) end
  self.count = #self.entries
  self.dirty = true
end

function L:list()
  local out = {}
  for i, e in ipairs(self.entries) do out[i] = e end
  return out
end

-- One entry as a line of Lua: strings, numbers and booleans only, keys in order.
local function line(e)
  local keys = {}
  for k, v in pairs(e) do
    local t = type(v)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") and (t == "string" or t == "number" or t == "boolean") then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = e[k]
    local s
    if type(v) == "string" then s = ("%q"):format(v):gsub("\\\n", "\\n")
    elseif math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then s = ("%d"):format(v)
    else s = tostring(v) end
    parts[#parts + 1] = k .. " = " .. s
  end
  return "  { " .. table.concat(parts, ", ") .. " },"
end

function L:save()
  if not self.path or not self.dirty then return true end
  local out = { "-- lens-log.cfg: the alert log (LOG on the dashboard), newest first. Written by lens-hub.",
    "return { entries = {" }
  for _, e in ipairs(self.entries) do out[#out + 1] = line(e) end
  out[#out + 1] = "} }"
  local ok, err = files.writeAtomic(self.path, table.concat(out, "\n") .. "\n")
  if not ok then return nil, err end
  self.dirty = false
  return true
end

return logbook
