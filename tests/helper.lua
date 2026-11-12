--[[ tests/helper.lua - shared setup for the test files

  local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")

  H.check(cond, msg)     assert with a readable "ok"/"FAIL" line
  H.run(file, ...)       run src/<file> with arguments
  H.exists(path)         whether a file exists
  H.screen(name)         dump the mock screen to $SCREENS/<name>.txt when SCREENS is set (make screens)
  H.glasses(name, G)     dump a glasses mock's visible widgets to $SCREENS/<name>.hud (tools/render_hud.py)
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

function H.screen(screenName)
  local dir = os.getenv("SCREENS")
  if dir then require("oc").dump(dir .. "/" .. screenName .. ".txt") end
end

function H.glasses(dumpName, G)
  local dir = os.getenv("SCREENS")
  if not dir then return end
  local f = assert(io.open(dir .. "/" .. dumpName .. ".hud", "w"))
  for _, s in ipairs(G.live()) do
    if s.visible then
      local c = s.color or { 1, 1, 1 }
      f:write(table.concat({ s.kind, s.x, s.y, s.w, s.h, c[1], c[2], c[3], s.alpha or 1, s.scale or 1,
        ((s.text or ""):gsub("[\t\n]", " ")) }, "\t"), "\n")
    end
  end
  f:close()
end

function H.done()
  print(("PASS %s (%d checks)"):format(H.NAME, H.passed))
end

return H
