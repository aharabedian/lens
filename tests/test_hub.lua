-- test_hub.lua: the hub's pure modules: store (nodes, series, counter rates, staleness), query (the
-- selector language), rules (hub alerts with `for`), alerts (merge, ack, ordering) and core health.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
require("oc")
local check = H.check
local store = require("lens.hub.store")
local query = require("lens.hub.query")
local rules = require("lens.hub.rules")
local alerts = require("lens.hub.alerts")

local function snap(node, boot, samples, extra)
  local m = { kind = "snapshot", node = node, role = node:match("^(%a+)"), boot = boot, seq = 1, dseq = 1,
    interval = 10, health = "ok", samples = samples, alerts = {} }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local function desc(node, boot, metrics, dseq)
  return { kind = "describe", node = node, role = node:match("^(%a+)"), boot = boot, seq = 1, dseq = dseq or 1,
    metrics = metrics }
end

---------------------------------------------------------------- store
do
  local s = store.new()
  local want = s:receive(snap("prism-ore", 1, { { "prism_backlog_items", 4200, { process = "ore" } } }), 0)
  check(want == "hello", "a snapshot before any describe asks the node to describe itself")
  check(s:receive(snap("prism-ore", 1, {}), 1) == nil, "the hello isn't repeated within an interval")
  check(s:receive(snap("prism-ore", 1, {}), 11) == "hello", "but is asked again an interval later")
  s:receive(desc("prism-ore", 1, { prism_routed_total = { type = "counter" }, prism_backlog_items = { type = "gauge" } }), 12)
  check(s:receive(snap("prism-ore", 1, { { "prism_backlog_items", 4200, { process = "ore" } },
    { "prism_routed_total", 100 } }), 20) == nil, "descriptors match: no hello")

  local b = s:lookup("prism_backlog_items", 20)
  check(#b == 1 and b[1].value == 4200 and b[1].labels.node == "prism-ore" and b[1].labels.process == "ore"
    and b[1].type == "gauge", "series carry their value, labels plus node, and type")
  check(s:lookup("prism_routed_total", 20)[1].rate == nil, "a counter's first sample has no rate")

  s:receive(snap("prism-ore", 1, { { "prism_routed_total", 150 } }), 30)
  check(s:lookup("prism_routed_total", 30)[1].rate == 5, "rate = increase / seconds between snapshots")
  check(#s:lookup("prism_backlog_items", 30) == 0, "a series missing from the latest snapshot is gone")
  s:receive(snap("prism-ore", 1, { { "prism_routed_total", 20 } }), 40)
  check(s:lookup("prism_routed_total", 40)[1].rate == nil, "a counter that went down has no rate")

  s:receive(snap("prism-ore", 2, { { "prism_routed_total", 30 } }), 50)
  check(s:lookup("prism_routed_total", 50)[1].rate == nil and s:lookup("prism_routed_total", 50)[1].type == "gauge",
    "a new boot drops the old descriptors and counter history")

  local n = s:nodes(50)[1]
  check(n.name == "prism-ore" and n.role == "prism" and n.health == "ok" and not n.stale and n.boot == 2,
    "nodes report name, role, health and boot")
  check(s:nodes(80)[1].health == "ok" and s:nodes(80.5)[1].health == "stale" and s:nodes(81)[1].stale,
    "a node is stale after 3 intervals without a snapshot")
  check(#s:lookup("prism_routed_total", 81) == 0, "a stale node's series aren't looked up")
  s:receive(snap("prism-ore", 2, { { "prism_routed_total", 40 } }, { health = "warn" }), 90)
  check(s:nodes(90)[1].health == "warn", "a stale node that reports again shows its own health")
  s:forget("prism-ore")
  check(#s:nodes(90) == 0, "forget drops a node")
end

---------------------------------------------------------------- query
local function series(name, value, labels, extra)
  local s = { name = name, value = value, labels = labels or {}, type = "gauge" }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local DATA = {
  prism_machine_state = {
    series("prism_machine_state", 1, { node = "prism-ore", process = "ore", machine = "mac1", state = "running" }),
    series("prism_machine_state", 0, { node = "prism-ore", process = "ore", machine = "mac1", state = "down" }),
    series("prism_machine_state", 0, { node = "prism-ore", process = "ore", machine = "mac2", state = "running" }),
    series("prism_machine_state", 1, { node = "prism-ore", process = "ore", machine = "mac2", state = "down" }),
    series("prism_machine_state", 1, { node = "prism-ore", process = "ore_wash", machine = "w1", state = "running" }),
    series("prism_machine_state", 0, { node = "prism-ore", process = "ore_wash", machine = "w1", state = "down" }),
  },
  prism_backlog_items = {
    series("prism_backlog_items", 4000, { node = "prism-ore", process = "ore" }),
    series("prism_backlog_items", 200, { node = "prism-ore", process = "ore_wash" }),
  },
  power_eu_stored = { series("power_eu_stored", 2e9, { node = "power-main", bank = "lsc1" }) },
  power_eu_capacity = { series("power_eu_capacity", 1e10, { node = "power-main", bank = "lsc1" }) },
  power_eu_generated_total = {
    series("power_eu_generated_total", 5e6, { gen = "t1" }, { type = "counter", rate = 2048 }),
    series("power_eu_generated_total", 1e6, { gen = "t2" }, { type = "counter", rate = 512 }),
    series("power_eu_generated_total", 1e6, { gen = "t3" }, { type = "counter" }),
  },
}
local function lookup(name) return DATA[name] end
local function q(text)
  local f, err = query.compile(text)
  if not f then error("compile failed: " .. text .. ": " .. err, 2) end
  return f(lookup)
end

check(q('sum(prism_machine_state{process="ore", state="running"})') == 1, "sum with label matchers")
check(q('count(prism_machine_state{process="ore", state="running"})') == 2, "count counts series, not values")
check(q('sum(prism_machine_state{process=~"^ore", state="running"})') == 2, "=~ is a Lua pattern")
check(q('sum(prism_machine_state{process!~"wash", state!="down"})') == 1, "!~ and != exclude")
check(q('count(prism_machine_state{node="power-main"})') == 0, "count of nothing is 0")
check(q('sum(prism_machine_state{node="power-main"})') == nil and q('max(nothing_here)') == nil,
  "sum, max of nothing is nil")
check(q("prism_backlog_items") == 4200, "a bare selector is the sum of its series")
check(q("max(prism_backlog_items)") == 4000 and q("min(prism_backlog_items)") == 200
  and q("avg(prism_backlog_items)") == 2100, "max, min, avg")
check(q("power_eu_stored / power_eu_capacity") == 0.2, "arithmetic between selectors")
check(q("rate(power_eu_generated_total)") == 2560, "rate sums the counters that have a rate")
check(q("power_eu_stored / 0") == nil and q("nothing_here + 1") == nil, "division by zero and missing data give nil")
check(q("1 + 2 * 3") == 7 and q("(1 + 2) * 3") == 9 and q("-2 * -3") == 6 and q("10 / 4") == 2.5
  and q("1.5e3") == 1500, "numbers and precedence")
check(q("power_eu_stored / power_eu_capacity < 0.25 and prism_backlog_items > 0") == 1, "comparisons and and")
check(q("nothing_here > 0 or prism_backlog_items > 5000") == 0, "missing data is false in or")
check(q("not nothing_here > 0") == 1 and q("not prism_backlog_items > 0") == 0, "not")
check(q("prism_backlog_items == 4200") == 1 and q("prism_backlog_items != 4200") == 0, "== and !=")

local function bad(text, pattern)
  local f, err = query.compile(text)
  return f == nil and err:find(pattern, 1, true) ~= nil
end
check(bad("sum(prism_x", "expected )"), "unclosed call is reported")
check(bad('prism_x{a=b}', "quoted value"), "label values must be quoted")
check(bad('prism_x{a~"b"}', "unexpected '~'"), "unknown operator")
check(bad("1 +", "expected a number"), "missing operand")
check(bad("1 2", "expected end of query at 3"), "trailing tokens, with position")
check(bad('prism_x{a="b}', "unterminated string"), "unterminated string")
check(bad('prism_x{a=~"[a"}', "bad pattern"), "bad Lua pattern is caught at compile time")

---------------------------------------------------------------- rules
do
  local _, err = rules.new{ { id = "a", when = "1", level = "info" } }
  check(err == "rule a: level must be warn or bad", "rules: bad level")
  _, err = rules.new{ { id = "a", when = "1", level = "warn" }, { id = "a", when = "1", level = "warn" } }
  check(err == "rule a: id used twice", "rules: duplicate ids")
  _, err = rules.new{ { id = "a", when = "1 +", level = "warn" } }
  check(err and err:find("rule a: expected", 1, true), "rules: query errors name the rule")
  _, err = rules.new{ { when = "1", level = "warn" } }
  check(err == "rule 1: needs an id", "rules: missing id")

  local value = 0
  local function look(name) if name == "test_x" then return { series("test_x", value) } end end
  local r = assert(rules.new{
    { id = "hot", when = "test_x > 10", level = "bad", text = "Too hot", ["for"] = 30 },
    { id = "any", when = "test_x > 0", level = "warn" },
  })
  check(#r:evaluate(look, 0) == 0, "nothing fires while false")
  value = 20
  local f = r:evaluate(look, 100)
  check(#f == 1 and f[1].id == "any" and f[1].text == "any", "a rule without for fires at once; text defaults to id")
  f = r:evaluate(look, 129)
  check(#f == 1, "a rule with for waits")
  f = r:evaluate(look, 130)
  check(#f == 2 and f[1].id == "hot" and f[1].age == 0 and f[1].level == "bad" and f[1].text == "Too hot",
    "then fires once true for that long, age counting from then")
  value = 5
  check(#r:evaluate(look, 131) == 1, "false again: it stops")
  value = 20
  check(#r:evaluate(look, 132) == 1, "and the for timer starts over")
end

---------------------------------------------------------------- alerts
do
  local a = alerts.new()
  local r = a:update(100, {
    { node = "prism-ore", id = "down:mac2", level = "warn", text = "mac2 down", age = 30 },
    { node = "power-main", id = "lsc-low", level = "bad", text = "LSC low" },
  })
  check(r.changed and #r.new == 2 and #r.cleared == 0, "update reports new alerts")
  local l = a:list()
  check(l[1].key == "power-main/lsc-low" and l[2].key == "prism-ore/down:mac2" and l[2].since == 70,
    "bad first; since = now - age at first sighting")
  check(a:counts().bad == 1 and a:counts().warn == 1 and a:counts().unacked == 2, "counts")

  r = a:update(110, {
    { node = "prism-ore", id = "down:mac2", level = "warn", text = "mac2 down", age = 40 },
    { node = "power-main", id = "lsc-low", level = "bad", text = "LSC low" },
  })
  check(not r.changed and a:list()[2].since == 70, "nothing changed: changed is false and since stays")

  check(a:ack("prism-ore/down:mac2") and not a:ack("nope"), "ack by key")
  check(a:counts().unacked == 1, "acked alerts aren't counted as unacked")
  a:update(120, {
    { node = "prism-ore", id = "down:mac2", level = "warn", text = "mac2 down" },
    { node = "power-main", id = "lsc-low", level = "bad", text = "LSC low" },
  })
  check(a:list()[2].acked, "an ack lasts while the alert stays the same")
  r = a:update(130, {
    { node = "prism-ore", id = "down:mac2", level = "bad", text = "mac2 down for 5 min" },
    { node = "power-main", id = "lsc-low", level = "bad", text = "LSC low" },
  })
  local mac = a:list()[1]
  check(r.changed and mac.key == "prism-ore/down:mac2" and not mac.acked and mac.level == "bad",
    "getting worse undoes the ack; older bad alerts sort first")
  r = a:update(140, { { node = "power-main", id = "lsc-low", level = "bad", text = "LSC low" } })
  check(r.changed and r.cleared[1] == "prism-ore/down:mac2" and #a:list() == 1, "an alert that stops is cleared")
  a:update(150, {
    { node = "prism-ore", id = "down:mac2", level = "warn", text = "mac2 down" },
    { node = "power-main", id = "lsc-low", level = "bad", text = "LSC low" },
  })
  check(not a:list()[2].acked and a:list()[2].since == 150, "an alert that comes back is new again")
  a:ackAll()
  check(a:counts().unacked == 0, "ackAll")
end

H.done()
