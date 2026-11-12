-- test_net.lua: agents and the hub over the simulated network (mocks/net.lua): the mock's packet limits,
-- discovery with hello, big snapshots in parts, lost packets, stale nodes, restarts, tokens, and hub
-- queries, rules and health over real traffic.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local codec = require("lens.codec")
local metrics = require("lens.metrics")
local core = require("lens.hub.core")
local net = require("net")

local PORT = codec.DEFAULT_PORT

local function raises(fn, pattern)
  local ok, err = pcall(fn)
  return not ok and tostring(err):find(pattern, 1, true) ~= nil
end

---------------------------------------------------------------- the mock itself
do
  local n = net.new()
  local a, b, c = n:endpoint("a"), n:endpoint("b"), n:endpoint("c")
  check(b.open(PORT) and not b.open(PORT), "open returns false when the port is already open")
  a.broadcast(PORT, "hi")
  check(#b.inbox == 1 and #c.inbox == 0 and #a.inbox == 0,
    "broadcast reaches endpoints with the port open, not the sender")
  local ev = n.pop(b)
  check(ev[1] == "modem_message" and ev[2] == "b" and ev[3] == "a" and ev[4] == PORT and ev[6] == "hi",
    "events look like OpenComputers' modem_message")
  c.open(PORT)
  a.send("c", PORT, "just you")
  check(#b.inbox == 0 and #c.inbox == 1, "send reaches only the named address")
  check(raises(function() a.broadcast(PORT, string.rep("x", 8193)) end, "packet too big (max 8192)"),
    "packets over maxPacketSize raise")
  check(raises(function() a.broadcast(PORT, 1, 2, 3, 4, 5, 6, 7, 8, 9) end, "too many parts"), "at most 8 values")
end

---------------------------------------------------------------- an agent and the hub, wired to the mock
local function newAgent(n, o)
  local ag = { modem = n:endpoint(o.node), m = metrics.new{ role = o.role, clock = function() return M.time end } }
  ag.enc = codec.encoder{ node = o.node, role = o.role, boot = o.boot or 1, interval = o.interval or 10, token = o.token }
  ag.modem.open(PORT)
  ag.token = o.token
  function ag.broadcast(packets) for _, p in ipairs(packets) do ag.modem.broadcast(PORT, p) end end
  function ag.describe() ag.broadcast(ag.enc:describe(ag.m:describe())) end
  function ag.push() ag.broadcast(ag.enc:snapshot(ag.m:snapshot())) end
  -- What an agent's event loop does with incoming messages: answer hello with describe + snapshot.
  function ag.handle()
    local ev = n.pop(ag.modem)
    while ev do
      local msg = codec.decode(ev[6], ag.token)
      if msg and msg.kind == "hello" then ag.describe(); ag.push() end
      ev = n.pop(ag.modem)
    end
  end
  return ag
end

local function newHub(n, o)
  local hub = assert(core.new(o))
  local modem = n:endpoint("hub")
  modem.open(PORT)
  -- What the hub's event loop does: feed every packet to core, send its replies.
  local function pump()
    local ev = n.pop(modem)
    while ev do
      for _, r in ipairs(hub:receive(ev[6], ev[3], M.time)) do modem.send(r.to, PORT, r.data) end
      ev = n.pop(modem)
    end
  end
  return hub, modem, pump
end

local function oreAgent(ag, machines)
  local state = ag.m:gauge("prism_machine_state", "Machine state")
  local backlog = ag.m:gauge("prism_backlog_items", "Items waiting", "items")
  local routed = ag.m:counter("prism_items_routed_total", "Items moved", "items")
  return function(b, downList, moved)
    ag.m:beginCycle()
    backlog:set(b, { process = "ore" })
    routed:add(moved or 0)
    for i = 1, machines do
      local name = "mac" .. i
      local down = downList and downList[name]
      for _, st in ipairs({ "running", "idle", "down" }) do
        state:set(((down and st == "down") or (not down and st == "running")) and 1 or 0,
          { process = "ore", machine = name, state = st })
      end
      if down then ag.m:alert("down:" .. name, "warn", name .. " stopped with work waiting") end
    end
  end
end

do
  M.setTime(0)
  local n = net.new()
  local hub, _, pump = newHub(n, {
    node = "hub", boot = 7,
    rules = { { id = "ore-stuck", when = 'prism_backlog_items > 1000 and sum(prism_machine_state{state="down"}) == 0',
      level = "warn", text = "Backlog but nothing is down", ["for"] = 0 } },
  })
  local ore = newAgent(n, { node = "prism-ore", role = "prism" })
  local cycle = oreAgent(ore, 150)    -- 450 machine-state series: several packets

  -- The hub has never seen this agent: its first snapshot arrives without descriptors.
  cycle(5000, nil, 0)
  ore.push()
  pump()
  check(#n.sent > 0 and #hub:nodes(0) == 1, "the hub hears a snapshot")
  ore.handle()
  pump()
  local node = hub:nodes(0)[1]
  check(node.dseq == ore.m.dseq and node.metrics.prism_machine_state.type == "gauge",
    "the hub asks a node it has no descriptors for to describe itself, and it does")
  check(hub:query('count(prism_machine_state{state="running"})', 0) == 150
    and hub:query('sum(prism_machine_state{state="running"})', 0) == 150,
    "a snapshot split over packets arrives whole")

  -- Lose one packet of the next snapshot: the hub keeps the previous one until the next arrives whole.
  M.setTime(10)
  cycle(4000, { mac2 = true }, 640)
  local count = 0
  n.drop = function() count = count + 1; return count == 2 end
  ore.push()
  n.drop = nil
  pump()
  check(hub:query("prism_backlog_items", 10) == 5000, "one lost part: the hub still has the last whole snapshot")
  M.setTime(20)
  cycle(3000, { mac2 = true }, 640)
  ore.push()
  pump()
  check(hub:query("prism_backlog_items", 20) == 3000
    and hub:query('sum(prism_machine_state{state="down"})', 20) == 1, "the next snapshot replaces it")
  check(hub:query("rate(prism_items_routed_total)", 20) == 1280 / 20,
    "counter rates span the lost snapshot (1280 items over 20 s)")

  local r = hub:tick(20)
  check(r.changed and r.new[1] == "prism-ore/down:mac2" and hub.alerts:list()[1].level == "warn",
    "an agent's alert shows up in the hub's list")
  check(hub:health(20) == "warn", "overall health follows the agent's health")

  -- Rules: backlog high and nothing down.
  M.setTime(30)
  cycle(3000, nil, 0)
  ore.push()
  pump()
  r = hub:tick(30)
  check(r.cleared[1] == "prism-ore/down:mac2" and r.new[1] == "hub/ore-stuck", "a cleared alert goes; a hub rule fires")

  -- Silence: the node goes stale.
  check(#hub:tick(60).new == 0, "30 s of silence with a 10 s interval is not stale yet")
  r = hub:tick(61)
  local l = hub.alerts:list()
  check(r.new[1] == "prism-ore/stale" and l[1].level == "bad" and l[1].text == "prism-ore stopped reporting"
    and l[1].since == 30, "after 3 intervals the node is stale: a bad alert, dating from the last snapshot")
  check(hub:health(61) == "bad" and hub:query("prism_backlog_items", 61) == nil,
    "a stale node makes health bad and its series disappear from queries")
  check(#hub:tick(62).new == 0 and not hub:tick(63).changed, "the stale alert doesn't churn each tick")

  -- Restart: new boot, seq starts over.
  M.setTime(70)
  local ore2 = newAgent(n, { node = "prism-ore", role = "prism", boot = 2 })
  local cycle2 = oreAgent(ore2, 2)
  cycle2(10, nil, 5)
  ore2.describe()
  ore2.push()
  pump()
  r = hub:tick(70)
  check(r.cleared[1] == "prism-ore/stale" and hub:query("count(prism_machine_state)", 70) == 6
    and hub:nodes(70)[1].boot == 2, "a restarted node is picked up at once (new boot, seq from 1)")
  check(hub:query("rate(prism_items_routed_total)", 70) == nil, "and its counter history starts over")
end

---------------------------------------------------------------- the hub starts after the agents
do
  M.setTime(0)
  local n = net.new()
  local power = newAgent(n, { node = "power-main", role = "power" })
  local stored = power.m:gauge("power_eu_stored", "EU stored", "EU")
  stored:set(5e8, { bank = "lsc1" })
  local hub, hubModem, pump = newHub(n, { node = "hub", boot = 3, nonCritical = { ["power-main"] = true } })
  hubModem.broadcast(PORT, hub:hello())
  power.handle()
  pump()
  check(hub:nodes(0)[1].dseq == 1 and hub:query("power_eu_stored", 0) == 5e8,
    "the hub's hello at start gets every agent to describe itself and report")
  check(hub:health(0) == "ok", "a healthy node: overall health ok")
  local r = hub:tick(31)
  check(r.new[1] == "power-main/stale" and hub.alerts:list()[1].level == "warn" and hub:health(31) == "ok",
    "a non-critical node going stale is a warning and doesn't affect overall health")
end

---------------------------------------------------------------- tokens
do
  M.setTime(0)
  local n = net.new()
  local hub, _, pump = newHub(n, { node = "hub", token = "lens-secret" })
  local good = newAgent(n, { node = "power-a", role = "power", token = "lens-secret" })
  local wrong = newAgent(n, { node = "power-b", role = "power", token = "prism-secret" })
  local none = newAgent(n, { node = "power-c", role = "power" })
  for _, ag in ipairs({ good, wrong, none }) do ag.m:gauge("power_eu_stored", "EU"):set(1); ag.push() end
  pump()
  local names = {}
  for _, nd in ipairs(hub:nodes(0)) do names[#names + 1] = nd.name end
  check(#names == 1 and names[1] == "power-a", "the hub ignores nodes without its token, even one using PRISM's")
end

---------------------------------------------------------------- the hub never answers a hub
do
  M.setTime(0)
  local n = net.new()
  local hub, _, pump = newHub(n, { node = "hub" })
  local other = n:endpoint("hub-2")
  other.open(PORT)
  other.broadcast(PORT, codec.encoder{ node = "hub-2", role = "hub", boot = 1 }:hello()[1])
  pump()
  check(#other.inbox == 0 and #hub:nodes(0) == 0, "a hello from another hub is ignored")
end

H.done()
