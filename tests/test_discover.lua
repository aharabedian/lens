-- test_discover.lua: lens-discover lists components, details their methods and docs into a file, skips the
-- basics unless asked, and filters by type.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check

M.components = {
  ["gp000000-0000"] = { type = "gpu", methods = { set = "function(x, y, value) -- write text" } },
  ["gl000000-0000"] = { type = "glasses", methods = {
    addText = "function(x, y, text):table -- a text widget", clear = "function() -- remove every widget" } },
  ["gt000000-0000"] = { type = "gt_machine", methods = { getEUStored = "function():number -- stored EU",
    isMachineActive = false } },
  ["bad00000-0000"] = { type = "broken_thing", methods = { explode = true } },
}
local realDoc = require("component").doc
require("component").doc = function(addr, m)
  if addr == "bad00000-0000" then error("doc failed") end
  return realDoc(addr, m)
end

local prefix = H.TMP .. "/root"
os.execute('mkdir -p "' .. prefix .. '/home"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LENS_PREFIX" then return prefix end return realGetenv(k) end

local function run(...)
  local lines, realPrint = {}, print
  print = function(...) lines[#lines + 1] = table.concat({ ... }, "\t") end
  local ok, err = pcall(H.run, "lens-discover.lua", ...)
  print = realPrint
  local f = io.open(prefix .. "/home/lens-discover.txt")
  local file = f and f:read("*a") or ""
  if f then f:close() end
  return ok, table.concat(lines, "\n"), file, err
end

local ok, out, file, err = run()
check(ok, "runs" .. (ok and "" or (": " .. tostring(err))))
check(out:find("glasses%s+gl000000%-0000 %(2 methods%)") and out:find("gpu%s+gp000000%-0000\n")
  and out:find("written to " .. prefix .. "/home/lens-discover.txt", 1, true), "prints every component; basics without methods")
check(file:find("== glasses gl000000-0000\n  addText  function(x, y, text):table -- a text widget\n  clear", 1, true),
  "the file has each method, sorted, with its doc")
check(file:find("  getEUStored  function():number -- stored EU\n  isMachineActive  \n", 1, true),
  "a method without a doc is still listed")
check(file:find("== broken_thing", 1, true) and file:find("  explode  \n", 1, true), "a doc that fails doesn't stop it")
check(not file:find("== gpu", 1, true), "basics aren't detailed by default")

local _
ok, _, file = run("--all")
check(ok and file:find("== gpu gp000000-0000\n  set  function(x, y, value)", 1, true), "--all details the basics too")

ok, out, file = run("glass")
check(ok and file:find("== glasses", 1, true) and not file:find("== gt_machine", 1, true)
  and out:find("gt_machine", 1, true), "a filter details only matching types, but still lists everything")

---------------------------------------------------------------- --widgets
-- The Glasses Terminal's add*() methods return objects whose methods we don't know yet. Model both kinds:
-- a Text2D that can be listed with pairs, and a Rect2D that only answers by name (like a userdata).
local objects, nextId = 0, 0
local function newWidget(fields)
  objects = objects + 1
  nextId = nextId + 1
  local id = nextId
  fields.getID = function() return id end
  return fields
end
local glasses = {
  getObjectCount = function() return objects end,
  removeObject = function() objects = objects - 1; return true end,
  removeAll = function() objects = 0 end,
  addTextLabel = function() return newWidget({ setText = function() end, addColor = function() end }) end,
  addRect = function()
    objects = objects + 1
    local known = { setSize = function() end, addTranslation = function() end }
    return setmetatable({}, { __index = function(_, k) return known[k] end })
  end,
  addQuad = function() error("not today") end,
}
M.components["gl000000-0000"].proxy = glasses
ok, out, file = run("--widgets")
check(ok and file:find("== addTextLabel() -> table\n    addColor  function\n    getID  function\n    setText  function", 1, true),
  "--widgets lists what a widget object offers")
check(file:find("    id 1, removed: true", 1, true), "a widget that tells its id is removed with removeObject")
check(file:find("== addRect() -> table", 1, true) and file:find("    setSize  function (found by name)", 1, true)
  and file:find("    addTranslation  function (found by name)", 1, true), "an object that can't be listed is tried by name")
check(file:find("== addQuad() failed: ", 1, true), "a widget that can't be made is reported")
check(file:find("removed the test widgets with removeAll() (there were none before)", 1, true) and objects == 0,
  "widgets without an id are cleared with removeAll when the HUD was empty")
check(out:find("setText", 1, true), "the widget report is printed too")

objects = 3
ok, _, file = run("--widgets")
check(ok and file:find("left 1 test widget(s): there were 3 before", 1, true) and objects == 4,
  "with other widgets present, removeAll isn't used")

---------------------------------------------------------------- --events
M.setTime(0)
local evs = { { "glasses_on", "gl000000-0000", "Aaron", n = 3 }, { "interact_overlay", "gl000000-0000", "Aaron", 12.5, 3, n = 5 } }
M.onPull = function(n) return evs[n] end
ok, out, file = run("--events", "5")
M.onPull = nil
check(ok and file:find('"glasses_on"  "gl000000-0000"  "Aaron"', 1, true)
  and file:find('"interact_overlay"  "gl000000-0000"  "Aaron"  12.5  3', 1, true), "--events records every event")
check(M.time >= 5 and out:find("printing every event for 5 s", 1, true), "for the given number of seconds")

---------------------------------------------------------------- --glasses-test
local G = require("glasses").new()
M.components["gl000000-0000"].proxy = G.proxy
M.setTime(0)
ok, out = run("--glasses-test", "10")
local bar, half, double = G.widgets[0], G.widgets[2], G.widgets[3]
check(ok and bar.kind == "rect" and bar.w == 80 and bar.h == 10 and bar.color[2] == 1,
  "--glasses-test draws a green bar, 80 wide and 10 tall with the height given first")
check(half.scale == 0.5 and half.text == "Scale 0.5" and double.scale == 2, "and text at scales 0.5 and 2")
check(out:find("Is the green bar wide and short", 1, true) and M.time >= 10,
  "says what to look for, and keeps the pattern up for the given time")
check(#G.live() == 0 and out:find("pattern removed", 1, true), "then removes it")

H.done()
