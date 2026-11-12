--[[ lens.hub.store: what the hub knows about each node, from decoded, whole lens/1 messages. Pure.

  local s = require("lens.hub.store").new{ staleAfter = 3 }
  s:receive(msg, now) -> "hello" | nil
      msg: a whole describe or snapshot (codec.assembler output). Returns "hello" when the hub should ask
      that node to describe itself again: its snapshot follows descriptors (boot, dseq) the hub doesn't
      have. At most once per node per interval.
  s:node(name) -> node | nil
  s:nodes(now) -> node[]   sorted by name
      node = { name, role, version, boot, interval, health, stale, lastSeen, alerts, moreAlerts, dseq, metrics }
      health is "stale" once no snapshot has arrived for staleAfter * interval seconds; stale is true then.
  s:lookup(name, now) -> series[]   the series of metric `name` on every node that isn't stale
      series = { name, value, labels, type, rate? }; labels include node = <node name>
      rate: for counters, per second since the previous snapshot of the same boot (nil on the first
      snapshot, after a restart, or when the value went down)
  s:forget(name)

  Series exist while the node sends them: each snapshot replaces all of a node's series.
  Metrics the hub has no descriptor for count as gauges.
]]

local store = {}

local Store = {}
Store.__index = Store

local DEFAULT_INTERVAL = 10

function store.new(opts)
  opts = opts or {}
  return setmetatable({ staleAfter = opts.staleAfter or 3, byName = {} }, Store)
end

local function seriesKey(name, labels)
  if not labels then return name end
  local keys = {}
  for k in pairs(labels) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = { name }
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(labels[k]) end
  return table.concat(parts, "\0")
end

local function nodeFor(self, msg)
  local n = self.byName[msg.node]
  if not n then
    n = { name = msg.node, series = {}, byMetric = {}, alerts = {}, health = "ok" }
    self.byName[msg.node] = n
  end
  if n.boot ~= msg.boot then
    -- A restart: counters start over and old descriptors no longer apply.
    n.boot, n.metrics, n.dseq, n.series, n.byMetric = msg.boot, nil, nil, {}, {}
  end
  n.role, n.version = msg.role, msg.version or n.version
  return n
end

local function describe(n, msg)
  n.metrics, n.dseq = msg.metrics or {}, msg.dseq
  -- Types may have changed: re-type the series we have.
  for _, s in pairs(n.series) do s.type = (n.metrics[s.name] or {}).type or "gauge" end
end

local function snapshot(n, msg, now)
  local old, series, byMetric = n.series, {}, {}
  local types = n.metrics or {}
  for _, sample in ipairs(msg.samples or {}) do
    local name, value, labels = sample[1], sample[2], sample[3]
    if type(name) == "string" and type(value) == "number" then
      local l = {}
      if type(labels) == "table" then for k, v in pairs(labels) do l[k] = tostring(v) end end
      l.node = n.name
      local key = seriesKey(name, l)
      local s = { name = name, value = value, labels = l, type = (types[name] or {}).type or "gauge", at = now }
      local prev = old[key]
      if s.type == "counter" and prev and value >= prev.value and now > prev.at then
        s.rate = (value - prev.value) / (now - prev.at)
      end
      series[key] = s
      byMetric[name] = byMetric[name] or {}
      table.insert(byMetric[name], s)
    end
  end
  n.series, n.byMetric = series, byMetric
  n.interval = type(msg.interval) == "number" and msg.interval > 0 and msg.interval or n.interval or DEFAULT_INTERVAL
  n.health = msg.health
  n.alerts = type(msg.alerts) == "table" and msg.alerts or {}
  n.moreAlerts = msg.moreAlerts
  n.lastSeen = now

  if msg.dseq ~= n.dseq and (not n.helloAt or now - n.helloAt >= n.interval) then
    n.helloAt = now
    return "hello"
  end
end

function Store:receive(msg, now)
  if msg.kind ~= "describe" and msg.kind ~= "snapshot" then return nil end
  local n = nodeFor(self, msg)
  if msg.kind == "describe" then
    describe(n, msg)
    return nil
  end
  return snapshot(n, msg, now)
end

local function isStale(self, n, now)
  return not n.lastSeen or now - n.lastSeen > self.staleAfter * (n.interval or DEFAULT_INTERVAL)
end

function Store:node(name) return self.byName[name] end

function Store:nodes(now)
  local out = {}
  for _, n in pairs(self.byName) do
    n.stale = isStale(self, n, now)
    out[#out + 1] = {
      name = n.name, role = n.role, version = n.version, boot = n.boot, interval = n.interval,
      health = n.stale and "stale" or n.health, stale = n.stale, lastSeen = n.lastSeen,
      alerts = n.alerts, moreAlerts = n.moreAlerts, dseq = n.dseq, metrics = n.metrics,
    }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Store:lookup(name, now)
  local out = {}
  for _, n in pairs(self.byName) do
    if not isStale(self, n, now) then
      for _, s in ipairs(n.byMetric[name] or {}) do out[#out + 1] = s end
    end
  end
  return out
end

function Store:forget(name) self.byName[name] = nil end

return store
