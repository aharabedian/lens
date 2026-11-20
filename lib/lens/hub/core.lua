--[[ lens.hub.core: the hub without its screens or event loop. Pure apart from OpenOS `serialization`.

  local hub, err = require("lens.hub.core").new{
    node = "hub", boot = <random integer>, token = nil,
    staleAfter = 3,                         -- intervals of silence before a node is stale
    nonCritical = { ["prism-test"] = true },  -- nodes left out of overall health; their stale alert is a warn
    rules = { ... },                        -- lens.hub.rules
  }
  hub:hello() -> data                         broadcast once at start
  hub:receive(data, from, now, distance?) -> replies   from = sender's modem address; replies = { { to, data } }
      A snapshot that follows descriptors the hub doesn't have gets a hello sent back to that node.
      Messages that don't decode (other proto, wrong token, garbage) are ignored. distance: modem_message's.
  hub:traffic(name) -> { distance?, whole, cut } | nil   per node since the hub started: snapshots that arrived
      whole, and ones cut short (a part missing when the next snapshot began); the last packet's distance
  hub:forget(name)                            a node that stopped is dropped (it comes back if it reports)
  hub:remember(name, role?, interval?, now)   a node heard in an earlier run (store:remember)
  hub:drain() -> events                       store:drain(): nodes that restarted
  hub:tick(now) -> alerts:update result       call every second or so: stale nodes, agent alerts, rules
  hub:query(text, now) -> value | nil, err    compiled once per text
  hub:select(text, now) -> series[] | nil, err   a bare selector's series (state dots), compiled once per text
  hub:health(now, skip?) -> "ok" | "warn" | "bad"   worst over critical nodes; a stale critical node is bad;
                                              skip: { [name] = true } nodes left out (muted)
  hub:nodes(now)                              store:nodes(now)
  hub:metrics(now)                            store:metrics(now): what's there to query
  hub:lookup(now) -> fn(name) -> series[]     the store's series as queries see them
  hub.alerts                                  lens.hub.alerts (list, ack, counts)

  Alerts the hub raises itself use node = its own name for rules, and the silent node's name for
  id = "stale" ("not heard since hub start" for a remembered node that hasn't reported). An agent's
  moreAlerts becomes one warn with id = "more-alerts". A node that restarted RESTARTS times within an hour gets a
  warn with id = "restarts".
]]

local codec = require("lens.codec")
local store = require("lens.hub.store")
local query = require("lens.hub.query")
local rules = require("lens.hub.rules")
local alerts = require("lens.hub.alerts")

local core = {}

core.RESTARTS = 3

local Hub = {}
Hub.__index = Hub

function core.new(o)
  assert(type(o) == "table" and type(o.node) == "string", "hub needs a node name")
  local r, err = rules.new(o.rules)
  if not r then return nil, err end
  return setmetatable({
    node = o.node, token = o.token, nonCritical = o.nonCritical or {},
    enc = codec.encoder{ node = o.node, role = "hub", boot = o.boot or 1, token = o.token },
    asm = codec.assembler(), store = store.new{ staleAfter = o.staleAfter }, rules = r,
    alerts = alerts.new(), compiled = {}, selected = {}, snapshots = {},
  }, Hub)
end

function Hub:hello() return self.enc:hello()[1] end

-- Snapshots per node: part 1 starts one (the one before is cut short if it never came whole).
local function count(self, msg, whole, distance)
  local t = self.snapshots[msg.node]
  if not t then
    t = { whole = 0, cut = 0 }
    self.snapshots[msg.node] = t
  end
  if type(distance) == "number" then t.distance = distance end
  if msg.kind ~= "snapshot" then return end
  if (msg.part or 1) == 1 then
    if t.open then t.cut = t.cut + 1 end
    t.open = true
  end
  if whole then t.whole, t.open = t.whole + 1, false end
end

function Hub:receive(data, from, now, distance)
  local msg = codec.decode(data, self.token)
  if not msg or msg.kind == "hello" or msg.node == self.node then return {} end
  local whole = self.asm:add(msg, now)
  count(self, msg, whole, distance)
  if not whole then return {} end
  if self.store:receive(whole, now) == "hello" and from then
    return { { to = from, data = self:hello() } }
  end
  return {}
end

function Hub:lookup(now)
  return function(name) return self.store:lookup(name, now) end
end

function Hub:tick(now)
  self.startedAt = self.startedAt or now
  local active = {}
  for _, n in ipairs(self.store:nodes(now)) do
    local recent = 0
    for _, t in ipairs(n.restarts or {}) do if now - t <= 3600 then recent = recent + 1 end end
    if recent >= core.RESTARTS then
      active[#active + 1] = { node = n.name, id = "restarts", level = "warn",
        text = ("%s: %d restarts in an hour"):format(n.name, recent) }
    end
    if n.stale then
      local silent = math.floor(now - (n.lastSeen or n.rememberedAt or self.startedAt))
      active[#active + 1] = { node = n.name, id = "stale", level = self.nonCritical[n.name] and "warn" or "bad",
        text = n.name .. (n.lastSeen and " stopped reporting" or " not heard since hub start"), age = silent }
    else
      for _, a in ipairs(n.alerts or {}) do
        if type(a) == "table" and a.id ~= nil then
          active[#active + 1] = { node = n.name, id = a.id, level = a.level, text = a.text, age = a.age }
        end
      end
      if type(n.moreAlerts) == "number" and n.moreAlerts > 0 then
        active[#active + 1] = { node = n.name, id = "more-alerts", level = "warn",
          text = ("%d more alerts on %s"):format(n.moreAlerts, n.name) }
      end
    end
  end
  for _, a in ipairs(self.rules:evaluate(self:lookup(now), now)) do
    active[#active + 1] = { node = self.node, id = a.id, level = a.level, text = a.text, age = a.age }
  end
  return self.alerts:update(now, active)
end

function Hub:query(text, now)
  local q = self.compiled[text]
  if not q then
    local err
    q, err = query.compile(text)
    if not q then return nil, err end
    self.compiled[text] = q
  end
  return q(self:lookup(now))
end

function Hub:select(text, now)
  local s = self.selected[text]
  if not s then
    local err
    s, err = query.select(text)
    if not s then return nil, err end
    self.selected[text] = s
  end
  return s(self:lookup(now))
end

local RANK = { ok = 0, warn = 1, bad = 2, stale = 2 }

function Hub:health(now, skip)
  local worst = 0
  for _, n in ipairs(self.store:nodes(now)) do
    if not self.nonCritical[n.name] and not (skip and skip[n.name]) then worst = math.max(worst, RANK[n.health] or 0) end
  end
  return ({ [0] = "ok", "warn", "bad" })[worst]
end

function Hub:nodes(now) return self.store:nodes(now) end

function Hub:traffic(name)
  local t = self.snapshots[name]
  return t and { distance = t.distance, whole = t.whole, cut = t.cut } or nil
end

function Hub:remember(name, role, interval, now) self.store:remember(name, role, interval, now) end
function Hub:drain() return self.store:drain() end

function Hub:forget(name)
  self.store:forget(name)
  self.snapshots[name] = nil
end
function Hub:metrics(now) return self.store:metrics(now) end

return core
