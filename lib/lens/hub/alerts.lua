--[[ lens.hub.alerts: one list of every active alert in the base, with acknowledgements. Pure.

  local a = require("lens.hub.alerts").new()
  a:update(now, active) -> { new = { key... }, cleared = { key... }, changed = bool }
      active = { { node, id, level, text, age? } }: everything firing right now (agents' alerts, the hub's
      rules, stale nodes). An alert missing from `active` has cleared and is dropped.
      changed is true when anything a display shows (the set, a level, a text) differs from last time.
  a:list() -> { { key, node, id, level, text, since, acked } }   bad first, then oldest, then by key
  a:ack(key) -> bool      a:ackAll()
  a:counts() -> { bad, warn, unacked }

  key is node .. "/" .. id. since is when the condition started: now - age the first time it's seen, so an
  alert keeps its age when the hub restarts. An ack lasts until the alert clears or gets worse (warn -> bad).
]]

local alerts = {}

local SEVERITY = { warn = 1, bad = 2 }

local Alerts = {}
Alerts.__index = Alerts

function alerts.new() return setmetatable({ byKey = {} }, Alerts) end

function Alerts:update(now, active)
  local seen, new, cleared, changed = {}, {}, {}, false
  for _, x in ipairs(active) do
    local key = tostring(x.node) .. "/" .. tostring(x.id)
    if not seen[key] then
      seen[key] = true
      local level = SEVERITY[x.level] and x.level or "warn"
      local a = self.byKey[key]
      if not a then
        a = { key = key, node = x.node, id = x.id, since = now - (tonumber(x.age) or 0) }
        self.byKey[key] = a
        new[#new + 1] = key
        changed = true
      elseif a.level ~= level or a.text ~= x.text then
        changed = true
      end
      if a.acked and SEVERITY[level] > SEVERITY[a.ackedLevel] then a.acked, a.ackedLevel = false, nil end
      a.level, a.text = level, x.text
    end
  end
  for key in pairs(self.byKey) do
    if not seen[key] then
      self.byKey[key] = nil
      cleared[#cleared + 1] = key
      changed = true
    end
  end
  table.sort(new)
  table.sort(cleared)
  return { new = new, cleared = cleared, changed = changed }
end

function Alerts:list()
  local out = {}
  for _, a in pairs(self.byKey) do
    out[#out + 1] = { key = a.key, node = a.node, id = a.id, level = a.level, text = a.text, since = a.since,
      acked = a.acked or false }
  end
  table.sort(out, function(x, y)
    if x.level ~= y.level then return SEVERITY[x.level] > SEVERITY[y.level] end
    if x.since ~= y.since then return x.since < y.since end
    return x.key < y.key
  end)
  return out
end

function Alerts:ack(key)
  local a = self.byKey[key]
  if not a then return false end
  a.acked, a.ackedLevel = true, a.level
  return true
end

function Alerts:ackAll()
  for key in pairs(self.byKey) do self:ack(key) end
end

function Alerts:counts()
  local c = { bad = 0, warn = 0, unacked = 0 }
  for _, a in pairs(self.byKey) do
    c[a.level] = c[a.level] + 1
    if not a.acked then c.unacked = c.unacked + 1 end
  end
  return c
end

return alerts
