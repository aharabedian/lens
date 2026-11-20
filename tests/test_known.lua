-- test_known.lua: nodes the hub remembers and nodes that restart. On their own (store, core): a remembered node is
-- listed, goes stale only after staleAfter intervals and says it hasn't been heard since the hub started; a boot that
-- changes is a restart, and 3 in an hour a warn. Through lens-hub: a node missing after a restart is listed and
-- alerted on; a node's restarts are on LOG, its node page and the alerts. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local codec = require("lens.codec")
local core = require("lens.hub.core")
local files = require("lens.files")

---------------------------------------------------------------- on their own
do
  local hub = core.new{ node = "hub" }
  hub:remember("prism-nether-ore", "prism", 5, 100)
  local n = hub:nodes(110)[1]
  check(n.name == "prism-nether-ore" and not n.stale and n.role == "prism", "a remembered node is listed")
  check(#hub:tick(110).new == 0, "and not alerted on before it should have reported")
  local changes = hub:tick(120)
  local a = hub.alerts:list()[1]
  check(#changes.new == 1 and a.text == "prism-nether-ore not heard since hub start" and a.level == "bad"
    and math.floor(a.since) == 100, "after staleAfter intervals: stale, not heard since hub start")

  local function snap(boot, t)
    local enc = codec.encoder{ node = "prism-nether-ore", role = "prism", boot = boot, interval = 5 }
    for _, p in ipairs(enc:snapshot({ samples = {}, health = "ok" })) do hub:receive(p, "a", t) end
  end
  snap(3, 121)
  hub:tick(121)
  check(#hub.alerts:list() == 0 and #hub:drain() == 0, "when it reports: no alert, and no restart (no boot before)")
  for i, t in ipairs({ 200, 300, 400 }) do
    snap(3 + i, t)
    local ev = hub:drain()
    check(#ev == 1 and ev[1].kind == "restart" and ev[1].node == "prism-nether-ore" and ev[1].at == t,
      ("a new boot is a restart (%d)"):format(i))
    hub:tick(t)
  end
  local warn = hub.alerts:list()[1]
  check(warn and warn.id == "restarts" and warn.level == "warn" and warn.text == "prism-nether-ore: 3 restarts in an hour",
    "3 restarts in an hour: a warn")
  hub:tick(200 + 3601)
  check(#hub.alerts:list() == 1 and hub.alerts:list()[1].id == "stale", "it ends once they're more than an hour apart")
end

---------------------------------------------------------------- through lens-hub
local function ore(o)
  o = o or {}
  return R.agent{ node = "prism-ore", role = "prism", restartAt = o.restartAt, cycle = function(m)
    m:beginCycle()
    m:gauge("prism_backlog_items", "b", "items"):set(4200, { process = "ore" })
  end }
end
local nether = R.agent{ node = "prism-nether-ore", role = "prism", cycle = function(m)
  m:beginCycle()
  m:gauge("prism_backlog_items", "b", "items"):set(800, { process = "ore" })
end }

M.setTime(0)
local ok, err, dir = R.run{ cfg = "return {}", dir = "known", agents = { ore(), nether }, script = function(t)
  if t < 20 then return nil end
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
local saved = files.loadTable(dir .. "/lens-board.cfg")
check(saved and saved.nodes and saved.nodes["prism-nether-ore"] and saved.nodes["prism-nether-ore"].role == "prism"
  and saved.nodes["prism-nether-ore"].interval == 5, "lens-board.cfg remembers the nodes heard")

-- Restarted without prism-nether-ore; prism-ore restarts three times.
local start = M.time
local seen = {}
ok, err = R.run{ cfg = "return {}", dir = "known", keep = true,
  agents = { ore{ restartAt = { start + 30, start + 40, start + 50 } } }, keyboard = true, script = function(t)
  if t < start + 5 then return nil end
  if not seen.early then
    seen.early = true
    seen.listed = M.find("prism-nether-ore", 3) and M.find("2 nodes", 1) and not M.find("not heard", 3)
    return nil
  end
  if t < start + 60 then return nil end
  if not seen.later then
    seen.later = true
    seen.missing = M.find("prism-nether-ore not heard since hub start", 3) and M.find("STALE", 3)
    seen.restarts = M.find("prism-ore: 3 restarts in an hour", 3) ~= nil
    H.screen("known-dashboard")
    return R.tap(" LOG ", "Aaron", 1)
  end
  if not seen.log then
    seen.log = true
    seen.logged = M.find("prism-ore restarted", 3) and M.find(" NODE", 3)
    return R.tap("DONE", "Aaron", 1)
  end
  if not seen.node then
    seen.node = true
    local _, y = M.find("NODES", 2)
    return R.tap("prism-ore ", "Aaron", y)
  end
  seen.page = M.find("restarts since the hub started: 3, the last", 3) ~= nil
  return "stop"
end }
check(ok, "lens-hub restarts" .. (ok and "" or (": " .. tostring(err))))
check(seen.listed, "after a restart a remembered node is listed straight away, not yet alerted on")
check(seen.missing, "one that doesn't report: STALE, not heard since hub start")
check(seen.restarts, "3 restarts in an hour: a warn on the dashboard")
check(seen.logged, "each restart is on LOG")
check(seen.page, "and on the node's page")

H.done()
