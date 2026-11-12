--[[ tests/helper.lua - shared setup for the test files

  local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")

  H.check(cond, msg)     assert with a readable "ok"/"FAIL" line
  H.run(file, ...)       run src/<file> with arguments
  H.exists(path)         whether a file exists
  H.done()               print the summary line the runner looks for
  H.ROOT, H.SRC, H.TMP   repo root, src/, and a scratch directory for this test
]]

local H = {}
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
H.TESTS = here
H.ROOT  = here .. "/.."
H.SRC   = H.ROOT .. "/src"
package.path = here .. "/?.lua;" .. here .. "/mocks/?.lua;" .. here .. "/../lib/?.lua;" .. package.path

local name = (arg and arg[0] or "test"):match("([^/\\]+)%.lua$") or "test"
H.NAME = name
H.TMP = (os.getenv("TEST_TMP") or ((os.getenv("TMPDIR") or "/tmp") .. "/lens-tests")) .. "/" .. name
os.execute('rm -rf "' .. H.TMP .. '" && mkdir -p "' .. H.TMP .. '"')

H.passed = 0
function H.check(cond, msg)
  if not cond then error("FAIL: " .. msg, 2) end
  H.passed = H.passed + 1
  print("  ok  " .. msg)
end

function H.run(file, ...)
  local chunk = assert(loadfile(H.SRC .. "/" .. file))
  return chunk(...)
end

function H.exists(path)
  local f = io.open(path)
  if f then f:close(); return true end
  return false
end

function H.done()
  print(("PASS %s (%d checks)"):format(H.NAME, H.passed))
end

return H
