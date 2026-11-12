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

H.done()
