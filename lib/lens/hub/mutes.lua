--[[ lens.hub.mutes: muted nodes and alerts. A mute only changes what the hub shows and beeps: the agent keeps
  raising its alerts and nothing is sent to it. Pure; times are real seconds (lens.hub.clock).

  local mu = require("lens.hub.mutes").new(saved?)   saved: mu:list() from an earlier run (lens-board.cfg)
  mu:add{ node, key?, ends?, by, at }   a node (no key) or one alert (key = node .. "/" .. id). ends: when it ends
                                        (nil: when it clears: the alert, or every alert of the node). Replaces a
                                        mute of the same node or alert
  mu:remove(node, key?) -> mute | nil
  mu:expire(now, alerts) -> { mute... }   mutes that ended: past `ends`, or until-it-clears ones whose alert (or
                                        node's alerts) cleared. alerts: the alerts happening now ({ key, node })
  mu:of(alert) -> mute | nil            the mute that covers an alert ({ node, key }): its own, else its node's
  mu:node(name) -> mute | nil           the node's own mute
  mu:list() -> { mute... }              to save
  mutes.DURATIONS                       { 3600, 4 * 3600, 24 * 3600 }: the choices offered
]]

local mutes = {}

mutes.DURATIONS = { 3600, 4 * 3600, 24 * 3600 }

local Mutes = {}
Mutes.__index = Mutes

local function valid(m)
  return type(m) == "table" and type(m.node) == "string" and (m.key == nil or type(m.key) == "string")
    and (m.ends == nil or type(m.ends) == "number")
end

function mutes.new(saved)
  local self = setmetatable({ items = {} }, Mutes)
  for _, m in ipairs(type(saved) == "table" and saved or {}) do
    if valid(m) then self.items[#self.items + 1] = m end
  end
  return self
end

local function same(m, node, key) return m.node == node and m.key == key end

function Mutes:remove(node, key)
  for i, m in ipairs(self.items) do
    if same(m, node, key) then return table.remove(self.items, i) end
  end
end

function Mutes:add(m)
  self:remove(m.node, m.key)
  self.items[#self.items + 1] = { node = m.node, key = m.key, ends = m.ends, by = m.by, at = m.at }
end

function Mutes:expire(now, alerts)
  local keys, nodes = {}, {}
  for _, a in ipairs(alerts) do keys[a.key], nodes[a.node] = true, true end
  local keep, ended = {}, {}
  for _, m in ipairs(self.items) do
    local over
    if m.ends then over = now >= m.ends
    elseif m.key then over = not keys[m.key]
    else over = not nodes[m.node] end
    if over then ended[#ended + 1] = m else keep[#keep + 1] = m end
  end
  self.items = keep
  return ended
end

function Mutes:node(name)
  for _, m in ipairs(self.items) do if m.node == name and not m.key then return m end end
end

function Mutes:of(alert)
  for _, m in ipairs(self.items) do if m.key and m.key == alert.key then return m end end
  return self:node(alert.node)
end

function Mutes:list()
  local out = {}
  for i, m in ipairs(self.items) do out[i] = { node = m.node, key = m.key, ends = m.ends, by = m.by, at = m.at } end
  return out
end

return mutes
