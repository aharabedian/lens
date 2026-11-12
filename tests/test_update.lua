-- test_update.lua: lens-update installs what manifest.lua lists from the latest release of aharabedian/lens
-- (main when there are no releases), can follow a branch, a tag or a fork, keeps lens-hub.cfg, and refuses
-- broken downloads and manifests without touching what's installed.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check

local prefix = H.TMP .. "/root"
os.execute('mkdir -p "' .. prefix .. '/home"')

-- route LENS_PREFIX to the temp dir, and turn os.exit into a catchable error
local realGetenv = os.getenv
os.getenv = function(k) if k == "LENS_PREFIX" then return prefix end return realGetenv(k) end
os.exit = function(code) error({ exit = code }) end
local errors = {}
io.stderr = { write = function(_, s) errors[#errors + 1] = s end }

local SOURCES = { "manifest.lua" }
for _, f in ipairs(dofile(H.ROOT .. "/manifest.lua")) do SOURCES[#SOURCES + 1] = f[1] end
local function read(path) local h = io.open(path); if not h then return nil end; local s = h:read("*a"); h:close(); return s end

-- Serve the repo's files at repo@ref. `version` goes into lib/lens/version.lua, to tell refs apart.
local function serve(repo, ref, version)
  local base = ("https://raw.githubusercontent.com/%s/%s/"):format(repo, ref)
  for _, f in ipairs(SOURCES) do
    local text = read(H.ROOT .. "/" .. f)
    if version and f == "lib/lens/version.lua" then text = text:gsub('return "[^"]*"', 'return "' .. version .. '"') end
    M.web[base .. f] = text
  end
  return base
end
local function api(repo) return ("https://api.github.com/repos/%s/releases/latest"):format(repo) end
local function release(repo, tag)
  M.web[api(repo)] = ('{"url":"x","tag_name":"%s","prerelease":false}'):format(tag)
end

local out
local function update(...)
  errors, M.requests = {}, {}
  local lines, realPrint = {}, print
  print = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end; lines[#lines + 1] = table.concat(p, "\t") end
  local ok, err = pcall(H.run, "lens-update.lua", ...)
  print = realPrint
  out = table.concat(lines, "\n") .. table.concat(errors)
  return ok, (type(err) == "table" and err.exit) or err
end
local function has(s) return out:find(s, 1, true) ~= nil end
local function installedVersion() return (read(prefix .. "/home/lib/lens/version.lua") or ""):match('return "([^"]*)"') end
local function saved()
  return M.serialization.unserialize(read(prefix .. "/home/.lens-update.cfg") or "") or {}
end

M.internet = false
local ok, code = update()
check(not ok and code == 1 and has("Internet Card"), "refuses to run without an Internet Card")
M.internet = nil

---------------------------------------------------------------- no releases yet: main
M.web = {}
serve("aharabedian/lens", "main", "0.1.0-main")
ok = update()
check(ok and has("main (no releases yet)") and installedVersion() == "0.1.0-main", "no releases yet: installs main")
check(read(prefix .. "/home/bin/lens-hub.lua") and read(prefix .. "/home/lib/lens/hub/core.lua")
  and read(prefix .. "/home/lens-hub.example.cfg"), "programs, modules and the example config are installed")
check(has("no /home/lens-hub.cfg yet: run lens-setup"), "points to lens-setup when there's no config")
check(saved().repo == "aharabedian/lens" and saved().ref == "latest", "remembers to follow releases")

---------------------------------------------------------------- a release appears
release("aharabedian/lens", "v0.1.0")
serve("aharabedian/lens", "v0.1.0", "0.1.0")
local cfg = assert(io.open(prefix .. "/home/lens-hub.cfg", "w"))
cfg:write("return { node = 'mine' }")
cfg:close()
ok = update()
check(ok and has("latest release v0.1.0") and installedVersion() == "0.1.0", "follows the latest release")
check(read(prefix .. "/home/lens-hub.cfg") == "return { node = 'mine' }" and not has("no /home/lens-hub.cfg"),
  "never touches lens-hub.cfg")

---------------------------------------------------------------- branch, fork
serve("aharabedian/lens", "dev", "0.2.0-dev")
ok = update("dev")
check(ok and installedVersion() == "0.2.0-dev" and saved().ref == "dev" and has("staying on dev"), "a branch, saved")
ok = update()
check(ok and installedVersion() == "0.2.0-dev", "and used next time")
release("someone/lens", "v9.0.0")
serve("someone/lens", "v9.0.0", "9.0.0")
ok = update("someone/lens")
check(ok and installedVersion() == "9.0.0" and saved().repo == "someone/lens", "a fork's latest release")
ok = update("aharabedian/lens", "latest")
check(ok and installedVersion() == "0.1.0", "back to the main repo")

---------------------------------------------------------------- broken downloads change nothing
local base = serve("aharabedian/lens", "v0.1.0", "0.1.0")
M.web[base .. "lib/lens/hub/core.lua"] = "this is not lua ("
ok, code = update()
check(not ok and code == 1 and has("doesn't look like valid Lua") and installedVersion() == "0.1.0",
  "a download that isn't Lua stops the update before anything is replaced")
M.web[base .. "lib/lens/hub/core.lua"] = nil
ok = update()
check(not ok and has("HTTP 404"), "a missing file stops the update")
serve("aharabedian/lens", "v0.1.0", "0.1.0")
M.web[base .. "manifest.lua"] = 'return { { "../../etc/passwd", "bin/x.lua" } }'
ok = update()
check(not ok and has("bad entry"), "a manifest pointing outside the repo is refused")
M.web[base .. "manifest.lua"] = nil
ok = update()
check(not ok and has("can't download manifest.lua"), "no manifest: refused")
ok, code = update("not a repo/x")
check(not ok and code == 1 and has("not a GitHub repo"), "bad repo names are refused")

H.done()
