--[[ lens.hub.rules: the hub's own alerts, from queries over every node's metrics. Pure.

  local r, err = require("lens.hub.rules").new{
    { id = "power-vs-ore", when = 'power_fill_ratio < 0.2 and sum(prism_backlog_items) > 0',
      level = "bad", text = "Low power while the ore line has work", ["for"] = 60 },
  }
  err names the first bad rule (missing id, duplicate id, bad level, query that doesn't compile).
  r:evaluate(lookup, now) -> { { id, level, text, age } }   the rules firing now

  A rule fires once `when` has been true (non-zero) for `for` seconds (default 0) in a row. Missing data is
  false, so a rule never fires because a node went quiet; the hub's stale alert covers that.
]]

local query = require("lens.hub.query")

local rules = {}

local Rules = {}
Rules.__index = Rules

function rules.new(list)
  local out, seen = {}, {}
  for i, r in ipairs(list or {}) do
    local where = "rule " .. i
    if type(r) ~= "table" or type(r.id) ~= "string" or r.id == "" then return nil, where .. ": needs an id" end
    where = "rule " .. r.id
    if seen[r.id] then return nil, where .. ": id used twice" end
    seen[r.id] = true
    if r.level ~= "warn" and r.level ~= "bad" then return nil, where .. ": level must be warn or bad" end
    local q, err = query.compile(r.when)
    if not q then return nil, where .. ": " .. tostring(err) end
    local hold = r["for"] or 0
    if type(hold) ~= "number" or hold < 0 then return nil, where .. ": for must be seconds" end
    out[#out + 1] = { id = r.id, level = r.level, text = tostring(r.text or r.id), q = q, hold = hold }
  end
  return setmetatable({ list = out, since = {} }, Rules)
end

function Rules:evaluate(lookup, now)
  local firing = {}
  for _, r in ipairs(self.list) do
    local v = r.q(lookup)
    if v ~= nil and v ~= 0 then
      self.since[r.id] = self.since[r.id] or now
      local age = now - self.since[r.id]
      if age >= r.hold then
        firing[#firing + 1] = { id = r.id, level = r.level, text = r.text, age = age - r.hold }
      end
    else
      self.since[r.id] = nil
    end
  end
  return firing
end

return rules
