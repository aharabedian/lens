-- test_rules.lua: alerts made on the screen. ruledraft, rules:keep and the board's rules on their own; through lens-hub:
-- EDIT > ALERTS lists lens-hub.cfg's rules read-only; + NEW is typed on the keyboard, NOW says whether it's true and
-- when it would fire, SAVE makes it fire on the dashboard and keeps it in lens-board.cfg; SAVE AS ALERT on a panel's
-- page starts from its status rule and on DATA from its query, CANCEL going back; DELETE ALERT. Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local ruledraft = require("lens.hub.ruledraft")
local rules = require("lens.hub.rules")
local board = require("lens.hub.board")
local config = require("lens.hub.config")
local files = require("lens.files")
local K = require("lens.hub.textfield").KEYS

---------------------------------------------------------------- on their own
do
  local d = ruledraft.draft()
  check(d.focus == "text" and d.level == "warn" and d.fields["for"] == "0", "a new draft: typing the text, warn, for 0")
  for _, c in utf8.codes("Ore high") do ruledraft.key(d, c, 0) end
  ruledraft.key(d, 0, K.enter)
  ruledraft.paste(d, "sum(x) > 5")
  ruledraft.key(d, 0, K.tab)
  ruledraft.key(d, 0, K.back)
  ruledraft.key(d, ("3"):byte(), 0)
  ruledraft.level(d)
  local r = ruledraft.rule(d)
  check(r and r.id == "ore-high" and r.text == "Ore high" and r.when == "sum(x) > 5" and r["for"] == 3 and r.level == "bad",
    "typed, pasted, Enter and Tab to the next field: a rule, its id from its text")
  d.fields.when = "sum(x >"
  check(select(2, ruledraft.rule(d)) ~= nil, "a query that doesn't compile says why")
  d.fields.when, d.fields["for"] = "1", "-2"
  check(select(2, ruledraft.rule(d)):find("For", 1, true), "For must be seconds")
  d.fields.text = "  "
  check(select(2, ruledraft.rule(d)):find("text", 1, true), "a text is needed")
  check(ruledraft.slug("Low power, while the ore line works!") == "low-power-while-the-ore-line-works", "slug")
  local wrapped = require("lens.hub.frame").wrap("It's raised when When is true for For seconds.", 20)
  check(#wrapped == 3 and wrapped[1] == "It's raised when" and wrapped[2] == "When is true for For" and wrapped[3] == "seconds.",
    "frame.wrap breaks at spaces")

  local old = rules.new({ { id = "a", when = "x > 1", level = "warn" }, { id = "b", when = "x > 2", level = "bad" } })
  local lookup = function() return { { value = 5, labels = {} } } end
  old:evaluate(lookup, 10)
  local new = rules.new({ { id = "a", when = "x > 1", level = "warn" }, { id = "b", when = "x > 3", level = "bad" } })
  new:keep(old)
  check(new:trueSince("a") == 10 and new:trueSince("b") == nil, "keep: a rule with the same id and query keeps its timer")

  local cfg = config.check({ rules = { { id = "power-vs-ore", when = "1", level = "bad" } } })
  local path = H.TMP .. "/board.cfg"
  local b = board.new(path, cfg)
  check(b:setRule({ id = "ore-high", text = "Ore high", when = "sum(x) > 5", level = "warn", ["for"] = 0 }), "setRule")
  check(select(2, b:setRule({ id = "power-vs-ore", when = "1", level = "warn" })):find("already", 1, true),
    "an id lens-hub.cfg uses is refused")
  local again = board.new(path, cfg)
  check(#again:rules() == 1 and #again:allRules() == 2 and again:allRules()[1].id == "power-vs-ore", "saved; read back after lens-hub.cfg's")
  check(again:deleteRule("ore-high") and #board.new(path, cfg):rules() == 0, "deleteRule")
end

---------------------------------------------------------------- through lens-hub
local ore = R.agent{ node = "prism-ore", role = "prism", cycle = function(m)
  m:beginCycle()
  m:gauge("prism_backlog_items", "b", "items"):set(15100, { process = "ore" })
end }

local CFG = [[return { node = "hub", panels = {
  { label = "Ore", value = "sum(prism_backlog_items)", unit = "items", status = {
    { "bad", "$value > 50000" }, { "warn", "$value > 10000" }, { "good", "1" } } },
}, rules = {
  { id = "power-vs-ore", when = "sum(prism_backlog_items) > 99999", level = "bad", text = "Ore line busy on low power" },
} }]]

M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
local seen = {}
local step = 0
local ok, err, dir = R.run{ cfg = CFG, agents = { ore }, keyboard = true, script = function(t)
  if t < 12 then return nil end
  step = step + 1
  if step == 1 then return R.tap(" EDIT ", "Aaron", 1) end
  if step == 2 then return R.tap(" ALERTS ", "Aaron", 1) end
  if step == 3 then
    H.screen("rule-cfg-list")
    seen.list = M.find("MADE HERE (0)", 3) and M.find("FROM lens-hub.cfg (1)", 3) and M.find("Ore line busy on low power", 3)
      and M.find("false now", 3) and M.find("sum(prism_backlog_items) > 99999", 3)
    return R.tap(" + NEW ", "Aaron", 1)
  end
  if step == 4 then
    seen.form = M.find("New alert", 1) and M.find("Text", 3) and M.find("When", 3) and M.find("For (s)", 3)
    R.queue(R.keys("Ore backlog high", "Aaron"))
    R.queue(R.key(K.enter, "Aaron"))
    R.queue(R.keys("sum(prism_backlog_items) > 10000", "Aaron"))
    R.queue(R.key(K.enter, "Aaron"))
    R.queue(R.key(K.back, "Aaron"))
    R.queue(R.keys("5", "Aaron"))
    return nil
  end
  if step == 5 then
    seen.now = M.find("True now: it fires if it stays true 5s more.", 3) ~= nil
    return R.tap(" WARN ", "Aaron", 3)
  end
  if step == 6 then
    seen.level = M.find(" BAD ", 3) ~= nil
    H.screen("rule-form")
    return R.tap(" SAVE ", "Aaron", 1)
  end
  if step == 7 then
    seen.saved = M.find("MADE HERE (1)", 3) and M.find("Ore backlog high", 3) and M.find(" EDIT ", 3)
    H.screen("rule-list")
    return R.tap("DONE", "Aaron", 1)
  end
  if step == 8 then seen.at = t; return nil end
  if not seen.waited then
    if t < seen.at + 7 then step = step - 1; return nil end
    seen.waited = true
  end
  if step == 9 then
    seen.fired = M.find("Ore backlog high", 3) and M.find(" BAD ", 3) and M.find("hub", 3)
    return R.tap("Ore ", "Aaron", 3)                        -- the panel
  end
  if step == 10 then return R.tap("SAVE AS ALERT", "Aaron", 10) end
  if step == 11 then
    seen.fromPanel = M.find("New alert", 1) and M.find("(sum(prism_backlog_items)) > 50000", 3) and M.find(" BAD ", 3)
    return R.tap("CANCEL", "Aaron", 1)
  end
  if step == 12 then
    seen.backToPanel = M.find("Panel: Ore", 1) ~= nil
    return R.tap("DONE", "Aaron", 1)
  end
  if step == 13 then return R.tap(" DATA ", "Aaron", 1) end
  if step == 14 then return R.tap("prism_backlog_items", "Aaron", 3) end
  if step == 15 then return R.tap("SAVE AS ALERT", "Aaron", 3) end
  if step == 16 then
    seen.fromData = M.find("New alert", 1) and M.find("> 0", 3)
    return R.tap("CANCEL", "Aaron", 1)
  end
  if step == 17 then
    seen.backToData = M.find("SAVE AS ALERT", 3) ~= nil
    return R.tap("DONE", "Aaron", 1)
  end
  if step == 18 then return R.tap(" EDIT ", "Aaron", 1) end
  if step == 19 then return R.tap(" ALERTS ", "Aaron", 1) end
  if step == 20 then
    seen.firingListed = M.find("firing", 3) ~= nil
    return R.tap(" EDIT ", "Aaron", 4)
  end
  if step == 21 then
    seen.deleting = M.find("Alert: ore-backlog-high", 1) ~= nil
    return R.tap("DELETE ALERT", "Aaron", 3)
  end
  if step == 22 then
    seen.deleted = M.find("MADE HERE (0)", 3) ~= nil
    seen.deletedAt = t
    return R.tap("DONE", "Aaron", 1)
  end
  if t < seen.deletedAt + 2 then return nil end
  seen.gone = not M.find("Ore backlog high", 3)
  return "stop"
end }
M.aspect = nil
M.resize(160, 50)
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.list, "EDIT > ALERTS: lens-hub.cfg's rules read-only, with whether they're true")
check(seen.form, "+ NEW: Text, When, For")
check(seen.now, "NOW: true, and how long until it fires")
check(seen.level, "the level switches with a tap")
check(seen.saved, "SAVE lists it")
check(seen.fired, "and it fires on the dashboard, under the hub")
check(seen.fromPanel and seen.backToPanel, "SAVE AS ALERT on a panel's page starts from its first bad or warn rule; CANCEL goes back")
check(seen.fromData and seen.backToData, "SAVE AS ALERT on DATA starts from its query; CANCEL goes back")
check(seen.firingListed, "the list says it's firing")
check(seen.deleting and seen.deleted and seen.gone, "DELETE ALERT: gone from the list and the dashboard")
local saved = files.loadTable(dir .. "/lens-board.cfg")
check(saved and type(saved.rules) == "table" and #saved.rules == 0, "lens-board.cfg keeps the alerts (none left now)")

H.done()
