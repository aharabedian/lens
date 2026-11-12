-- test_hub.lua: the hub's pure modules: store (nodes, series, counter rates, staleness, the metric list), query
-- (the selector language), rules (hub alerts with `for`), alerts (merge, ack, ordering), format (values as
-- text and colors), config (views, HUD blocks, resolution), explore (queries by tapping), viewdraft (a view
-- being typed) and the screen's resolution fit.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
require("oc")
local check = H.check
local store = require("lens.hub.store")
local query = require("lens.hub.query")
local rules = require("lens.hub.rules")
local alerts = require("lens.hub.alerts")
local format = require("lens.hub.format")
local config = require("lens.hub.config")
local explore = require("lens.hub.explore")
local viewdraft = require("lens.hub.viewdraft")
local Gui = require("lens.gui")

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

---------------------------------------------------------------- format
do
  local function fv(view, v, total) return { format.view(view, v, total) } end
  check(fv({}, 1240000)[1] == "1.2M" and fv({ unit = "EU/t" }, 640)[1] == "640 EU/t" and fv({}, nil)[1] == "–",
    "auto: short numbers, the unit after")
  local r = fv({ format = "percent" }, 0.953)
  check(r[1] == "95%" and r[2] == 0.953, "percent: 0..1 as %, and the bar's fraction")
  check(fv({ format = "duration" }, 7500)[1] == "2h 05m" and fv({ format = "duration" }, 45)[1] == "45s"
    and fv({ format = "duration" }, 3 * 86400 + 3600)[1] == "3d 1h", "duration: seconds read naturally")
  r = fv({ format = "signed", unit = "EU/t", color = "sign" }, 2370)
  check(r[1] == "+2.4k EU/t" and r[3] == "good", "signed: a + above zero; color sign: green")
  r = fv({ format = "signed", unit = "EU/t", color = "sign" }, -2000)
  check(r[1] == "-2k EU/t" and r[3] == "bad", "below zero: red")
  check(fv({ color = "sign" }, 0)[3] == nil and fv({ color = "none", badAbove = 1 }, 5)[3] == nil, "zero, and none: no color")
  check(fv({ badBelow = 0.1, warnBelow = 0.25 }, 0.2)[3] == "warn" and fv({ max = 10 }, 20)[2] == 1,
    "thresholds as before; a bar's fraction stops at 1")
  check(fv({ of = "x", unit = "EU" }, 5e9, 1e10)[1] == "5G/10G EU" and fv({ of = "x" }, 5, 10)[2] == 0.5, "of: value/total")
end

---------------------------------------------------------------- config
do
  local c = assert(config.check({ hud = { blocks = {
    { anchor = "top", elements = {
      { kind = "bar", label = "Power", value = "1", format = "percent" },
      { kind = "text", label = "Net 5m", value = "2", format = "signed", color = "sign" },
      { kind = "gap" }, { kind = "alerts" } } },
    { anchor = "bottom-left", x = 30, y = -60 },
  } } }))
  local b1, b2 = c.hud.blocks[1], c.hud.blocks[2]
  check(b1.x == 0 and b1.y == 4 and b1.width == 160 and b1.elements[4].count == 3 and b2.x == 30 and b2.y == -60,
    "blocks: each anchor's default offset (4 in from its edges), width, alerts count")
  c = assert(config.check({ hud = { anchor = "bottom-right", x = 10, y = 20, alerts = 2,
    bars = { { label = "Ore", value = "1", max = 5 } } } }))
  b1 = c.hud.blocks[1]
  check(#c.hud.blocks == 1 and b1.anchor == "bottom-right" and b1.x == -10 and b1.y == -20
    and b1.elements[1].kind == "bar" and b1.elements[1].label == "Ore" and b1.elements[2].count == 2,
    "the first form (corner, margins, bars, alerts) becomes one block")
  local function err(t) local _, e = config.check(t); return e or "" end
  check(err({ hud = { blocks = { { anchor = "middle" } } } }):find("anchor must be one of", 1, true), "anchors are checked")
  check(err({ hud = { blocks = { { elements = { { kind = "dial" } } } } } }):find('kind must be "bar"', 1, true), "kinds are checked")
  check(err({ panels = { { label = "x", value = "1", format = "hex" } } }):find("format must be", 1, true)
    and err({ panels = { { label = "x", value = "1", color = "red" } } }):find("color must be", 1, true), "format and color are checked")
  check(assert(config.check({ panels = { { label = "x", value = "1", percent = true } } })).panels[1].format == "percent",
    "percent = true still works")
  check(err({ resolution = "big" }):find("resolution must be", 1, true) and config.check({}).resolution == "fit",
    "resolution: fit by default, checked")
end

---------------------------------------------------------------- explore
do
  check(explore.query("lumen_net_5m_eut", {}, "sum") == "sum(lumen_net_5m_eut)", "no filters: the metric")
  local text = explore.query("m", { lsc = 'Say "hi"\\', node = "power-room" }, "max")
  check(text == 'max(m{node="power-room", lsc="Say \\"hi\\"\\\\"})', "filters sorted (node first), quotes and backslashes escaped")
  local compiled = query.compile(text)
  check(compiled and compiled(function()
    return { { value = 7, labels = { node = "power-room", lsc = 'Say "hi"\\' } }, { value = 9, labels = { node = "x", lsc = "y" } } }
  end) == 7, "and the query reads back as the same value")
  local list = {
    { labels = { node = "power-room", lsc = "Main" } }, { labels = { node = "power-room", lsc = "Spare" } },
    { labels = { node = "power-base", lsc = "Main" } },
  }
  local labels = explore.labels(list, { node = "power-base" })
  check(labels[1].label == "node" and #labels[1].values == 2 and labels[1].chosen == "power-base"
    and labels[2].label == "lsc" and #labels[2].values == 1 and labels[2].values[1] == "Main",
    "labels: node first; choosing one narrows the others' values")
  check(explore.labelText({ lsc = "Main", node = "power-room" }) == "node=power-room lsc=Main", "label text, node first")
  check(explore.suggestLabel("lumen_net_5m_eut", { lsc = "Main", node = "x" }) == "net 5m eut · Main", "a starting label")
end

---------------------------------------------------------------- store:metrics
do
  local s = store.new{ staleAfter = 3 }
  s:receive({ kind = "describe", node = "a", boot = 1, metrics = { x_total = { type = "counter", help = "X done", unit = "items" } } }, 0)
  s:receive({ kind = "snapshot", node = "a", boot = 1, interval = 5, samples = { { "x_total", 3 }, { "y", 1, { k = "1" } }, { "y", 2, { k = "2" } } } }, 0)
  s:receive({ kind = "snapshot", node = "b", boot = 1, interval = 5, samples = { { "y", 5 } } }, 0)
  local ms = s:metrics(1)
  check(#ms == 2 and ms[1].name == "x_total" and ms[1].type == "counter" and ms[1].help == "X done" and ms[1].unit == "items"
    and ms[2].name == "y" and ms[2].series == 3 and #ms[2].nodes == 2 and ms[2].type == "gauge",
    "store:metrics: every metric, its type, help, unit, series and nodes")
  check(#s:metrics(100) == 0, "stale nodes' metrics are left out")
end

---------------------------------------------------------------- lens.hub.viewdraft
do
  local K = viewdraft.KEYS
  local d = viewdraft.draft()
  for _, c in utf8.codes("Net") do viewdraft.key(d, c, 0) end
  viewdraft.key(d, 0, K.enter)
  viewdraft.paste(d, "lumen_net_5m_eut\n")
  check(d.fields.label == "Net" and d.fields.value == "lumen_net_5m_eut " and d.focus == "value",
    "typing, Enter for the next field, pasting (line breaks become spaces)")
  viewdraft.key(d, 0, K.back)
  viewdraft.key(d, 0, K.back)
  check(d.fields.value == "lumen_net_5m_eu", "Backspace deletes")
  viewdraft.key(d, string.byte("t"), 0)
  viewdraft.cycle(d, "format"); viewdraft.cycle(d, "format"); viewdraft.cycle(d, "format")
  viewdraft.cycle(d, "color")
  check(d.choices.format == "signed" and d.choices.color == "sign", "choices cycle")
  viewdraft.focus(d, "warnBelow")
  viewdraft.key(d, string.byte("x"), 0)
  local v, verr = viewdraft.view(d)
  check(not v and verr == "Warn below must be a number", "numbers are checked")
  viewdraft.key(d, 0, K.back)
  viewdraft.paste(d, "-100")
  v = viewdraft.view(d)
  check(v and v.label == "Net" and v.value == "lumen_net_5m_eut" and v.format == "signed" and v.color == "sign"
    and v.warnBelow == -100 and v.unit == nil and v.max == nil, "a view: empty fields left out, defaults not written")
  d = viewdraft.draft({ label = "Power", value = "x / y", format = "percent", badBelow = 0.1 })
  check(d.fields.badBelow == "0.1" and d.choices.format == "percent" and d.choices.color == "thresholds", "a view's fields as text")
  d.fields.max, d.fields.of = "10", "y"
  check(select(2, viewdraft.view(d)) == "use Bar max or Bar of, not both", "max or of")
end

---------------------------------------------------------------- resolution
do
  local w, h = Gui.resolution(160, 50, 3, 4)
  check(w == 73 and h == 50, ("a 3 wide, 4 tall screen: 73 x 50 (got %d x %d)"):format(w, h))
  w, h = Gui.resolution(160, 50, 8, 3)
  check(w == 160 and h == 28, ("8 x 3: as wide as it goes, 160 x 28 (got %d x %d)"):format(w, h))
  check(select(1, Gui.resolution(80, 25, nil, nil)) == 80, "unknown shape: the largest")
end

---------------------------------------------------------------- several values, state dots, when
do
  local machines = function(name)
    if name == "m" then
      return { { value = 1, labels = { node = "a", machine = "mac1", state = "running" } },
               { value = 0, labels = { node = "a", machine = "mac1", state = "down" } },
               { value = 1, labels = { node = "a", machine = "mac2", state = "down" } },
               { value = 1, labels = { node = "a", machine = "mac3", state = "idle" } },
               { value = 1, labels = { node = "b", machine = "mac0", state = "warming" } } }
    end
    if name == "up" then return { { value = 1, labels = { node = "a", lsc = "Main" } }, { value = 0, labels = { node = "a", lsc = "Spare" } } } end
    return {}
  end
  local sel = query.select('m{node="a"}')
  check(sel and #sel(machines) == 4, "query.select: a selector's series themselves")
  check(select(2, query.select("sum(m)")) ~= nil, "query.select takes only a selector")
  local dots = format.dots(sel(machines))
  check(#dots == 3 and dots[1].name == "mac1" and dots[1].level == "good" and dots[2].level == "bad"
    and dots[3].level == "off", "dots: one per machine; by default running good, down bad, idle off")
  local mine = format.dots(sel(machines), "machine", { running = "good", idle = "warn", down = "off" })
  check(mine[1].level == "good" and mine[2].level == "off" and mine[3].level == "warn", "states: your own map of state to color")
  check(format.dots(query.select("m")(machines))[1].level == "warn", "an unknown state: warn")
  local ups = format.dots(machines("up"), "lsc")
  check(ups[1].name == "Main" and ups[1].level == "good" and ups[2].level == "bad", "no state label: above 0 good, else bad; by any label")
  check(format.template({ text = "{stored} / {cap} EU" }, { stored = 10773450724, cap = 11340000000 }) == "10.8G / 11.3G EU",
    "a template: each value formatted")
  check(format.template({ text = "{a} in, {b} out", format = "signed" }, { a = 2400, b = -1100 }) == "+2.4k in, -1.1k out",
    "with the view's format")
  check(format.template({ text = "{value} of {of}", format = "percent" }, { value = 0.5, of = 1 }) == "50% of 100%",
    "{value} and {of}")
  check(format.template({ text = "{x}", values = { x = "q" } }, {}) == "–", "a value with no data: –")
  local text, _, lv = format.view({ text = "{s}/{c}", values = { s = "1", c = "2" }, value = "v", badBelow = 5 }, 3, nil, { s = 5, c = 9 })
  check(text == "5/9" and lv == "bad", "format.view: the template's text, the value's level")

  local function err(t) local c, e = config.check(t); return c == nil and e or "" end
  check(config.check({ panels = { { label = "LSC", text = "{s} / {c}", values = { s = "a", c = "b" } } } }),
    "a view with text and values needs no value")
  check(config.check({ panels = { { label = "Ore", dots = 'prism_machine_state{node="x"}', by = "machine" } } }), "nor with dots")
  check(err({ panels = { { label = "x" } } }):find("needs a value", 1, true), "but with none of them, it's refused")
  check(err({ panels = { { label = "x", text = "{nope}" } } }):find("uses {nope}", 1, true), "a template's names must be in values")
  check(err({ panels = { { label = "x", text = "{a}", values = { a = "sum(" } } } }):find("values.a:", 1, true), "values are checked")
  check(err({ panels = { { label = "x", dots = "sum(x)" } } }):find("dots take a selector", 1, true), "dots take a selector")
  check(err({ panels = { { label = "x", value = "1", when = "x >" } } }):find("when:", 1, true), "when is checked")

  local d = viewdraft.draft({ label = "LSC", text = "{s} / {c} EU", values = { s = "sum(lumen_stored_eu)", c = "sum(lumen_capacity_eu)" } })
  check(d.fields.values == "c=sum(lumen_capacity_eu); s=sum(lumen_stored_eu)", "values typed as one line, name=query; ...")
  local v = viewdraft.view(d)
  check(v and v.values.s == "sum(lumen_stored_eu)" and v.values.c == "sum(lumen_capacity_eu)" and v.value == nil,
    "and read back")
  d.fields.values = "s sum(x)"
  check(select(2, viewdraft.view(d)):find("name=query", 1, true), "a malformed values line says how to write it")
end

---------------------------------------------------------------- alert history
do
  local a = alerts.new{ keep = 3 }
  a:update(10, { { node = "n", id = "x", level = "warn", text = "low" } })
  a:update(20, { { node = "n", id = "x", level = "bad", text = "very low" } })
  a:update(30, {})
  local h = a:history()
  check(#h == 1 and h[1].key == "n/x" and h[1].level == "bad" and h[1].text == "very low" and h[1].since == 10
    and h[1].ended == 30, "an alert that clears goes to history: its worst level, last text, start and end")
  for i = 1, 5 do
    a:update(40 + i, { { node = "n", id = "y" .. i, level = "warn", text = "t" } })
    a:update(41 + i, {})
  end
  h = a:history()
  check(#h == 3 and h[1].id == "y5" and h[3].id == "y3", "newest first, at most `keep`")
end

---------------------------------------------------------------- status rules
do
  local function err(t) local c, e = config.check(t); return c == nil and e or "" end
  check(format.expand("$value > 5 and $value < 9", "sum(x)") == "(sum(x)) > 5 and (sum(x)) < 9", "$value: the view's value query")
  local view = { label = "Ore", value = "sum(b)", status = {
    { "bad", "sum(down) > 0" }, { "warn", "$value > 50000" }, { "good", "sum(running) > 0" } } }
  check(config.check({ panels = { view } }), "status: a list of { level, query }")
  check(err({ panels = { { label = "x", value = "1", status = { { "purple", "1" } } } } }):find('starts with "good"', 1, true),
    "a rule's level is good, warn, bad or off")
  check(err({ panels = { { label = "x", status = { { "bad", "$value > 1" } } } } }):find("uses $value", 1, true),
    "$value needs the view to have a value")
  check(err({ panels = { { label = "x", value = "1", status = { { "bad", "x >" } } } } }):find("status rule 1", 1, true),
    "a rule's query is checked")
  check(err({ panels = { { label = "x", value = "1", color = "status" } } }):find("needs status rules", 1, true),
    'color = "status" needs rules')
  check(err({ panels = { { label = "x", dots = "m", states = { running = "green" } } } }):find("states:", 1, true),
    "states map to the four levels")
  local App = require("lens.hub.app")
  local data = {}
  local function run(text)
    local f = query.compile(text)
    return f(function(name) return data[name] or {} end)
  end
  local function at(down, backlog, running)
    data = { down = { { value = down, labels = {} } }, b = { { value = backlog, labels = {} } },
      running = { { value = running, labels = {} } } }
    return App.evaluateWith(view, run, function() return {} end)
  end
  check(at(1, 60000, 3).status == "bad", "the first true rule wins: down")
  check(at(0, 60000, 3).status == "warn", "then overflow ($value > 50000)")
  check(at(0, 4200, 3).status == "good", "then running")
  local idle = at(0, 4200, 0)
  check(idle.status == "off" and idle.level == nil and idle.text == "4.2k", "none true: off; the value keeps its own color")
  view.color = "status"
  check(at(0, 60000, 3).level == "warn", 'color = "status": the value takes the status color')
  view.color = nil

  local d = viewdraft.draft(view)
  check(#d.rules == 3 and d.rules[2][1] == "warn" and d.rules[2][2] == "$value > 50000", "the draft: rules as rows, in order")
  local back = viewdraft.view(d)
  check(back and back.status[2][1] == "warn" and back.status[2][2] == "$value > 50000", "and back to rules")
  viewdraft.ruleLevel(d, 2)
  check(d.rules[2][1] == "bad", "a rule's color cycles good, warn, bad, off")
  viewdraft.moveRule(d, 2, -1)
  check(d.rules[1][2] == "$value > 50000" and d.rules[2][2] == "sum(down) > 0", "rules move")
  viewdraft.removeRule(d, 1)
  viewdraft.addRule(d)
  check(#d.rules == 3 and d.rules[3][1] == "good" and d.focus == "rule:3", "+ RULE: a new row, typed into")
  for _, c in utf8.codes("sum(x) > 1") do viewdraft.key(d, c, 0) end
  check(d.rules[3][2] == "sum(x) > 1", "typing fills the rule's query")
  viewdraft.addRule(d)                                    -- left empty: dropped
  back = viewdraft.view(d)
  check(#back.status == 3 and back.status[3][2] == "sum(x) > 1", "empty rules are left out")
  viewdraft.addState(d)
  for _, c in utf8.codes("idle") do viewdraft.key(d, c, 0) end
  viewdraft.stateLevel(d, 1); viewdraft.stateLevel(d, 1); viewdraft.stateLevel(d, 1)
  back = viewdraft.view(d)
  check(back.states and back.states.idle == "off", "dot states: a name and a color per row")
  local dd = viewdraft.draft({ label = "x", dots = "m", states = { running = "good", down = "bad" } })
  check(#dd.states == 2 and dd.states[1][1] == "down" and dd.states[2][2] == "good", "states come in as rows, by name")
  viewdraft.removeState(dd, 1)
  check(viewdraft.view(dd).states.down == nil, "and go")
end

---------------------------------------------------------------- typing with a cursor
do
  local textfield = require("lens.hub.textfield")
  local K = textfield.KEYS
  local t, c = "sum(lumen_stored)", nil
  t, c = textfield.key(t, c, 0, K.left)
  t, c = textfield.key(t, c, 0, K.left)
  check(c == 15, "← moves the cursor back")
  for _, ch in utf8.codes("_eu") do t, c = textfield.key(t, c, ch, 0) end
  check(t == "sum(lumen_store_eud)" and c == 18, "typing inserts at the cursor")
  t, c = textfield.key("sum(lumen_storedd)", 17, 0, K.back)
  check(t == "sum(lumen_stored)" and c == 16, "Backspace deletes before the cursor")
  t, c = textfield.key("xsum(a)", 0, 0, K.delete)
  check(t == "sum(a)" and c == 0, "Delete deletes after it")
  c = select(2, textfield.key("abc", 1, 0, K["end"]))
  check(c == 3 and select(2, textfield.key("abc", 2, 0, K.home)) == 0, "Home and End")
  c = select(2, textfield.key("abc", 3, 0, K.right))
  check(c == 3 and select(2, textfield.key("abc", 0, 0, K.left)) == 0, "← → stop at the ends")
  t, c = textfield.paste("a d", 2, "b c\n")
  check(t == "a b c d" and c == 6, "a paste goes in at the cursor")
  t, c = textfield.key("abcd", 2, string.byte("x"), 0, 4)
  check(t == "abcd" and c == 2, "max: no more characters")
  local frame = require("lens.hub.frame")
  check(frame.window(5, 5, 10) == 1 and frame.window(30, 30, 10) == 22 and frame.window(30, 0, 10) == 1
    and frame.window(30, 15, 10) == 7, "a long field scrolls so the cursor shows")
  local d = viewdraft.draft({ label = "Net 5m", value = "x" })
  viewdraft.focus(d, "label", 3)
  viewdraft.key(d, string.byte("!"), 0)
  check(d.fields.label == "Net! 5m" and d.cursor == 4, "the view editor types at the cursor")
  viewdraft.key(d, 0, K.down)
  check(d.focus == "value" and d.cursor == 1, "↓ (and Enter) go to the next field, the cursor at its end")
  viewdraft.key(d, 0, K.up)
  check(d.focus == "label", "↑ goes back")
end

H.done()
