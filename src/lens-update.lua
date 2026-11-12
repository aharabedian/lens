--[[ lens-update.lua - install or update LENS from GitHub

  First time (needs an Internet Card):
    wget -f https://raw.githubusercontent.com/aharabedian/lens/main/src/lens-update.lua /home/lens-update.lua
    /home/lens-update

  After that:
    lens-update                  update from the saved source (default: latest release of aharabedian/lens)
    lens-update latest           follow releases
    lens-update main             follow the main branch (newest, may be unfinished)
    lens-update v0.3.0           install that release and stay on it
    lens-update OWNER/REPO [REF] use a fork: its latest release, or a branch/tag
  The choice is saved for next time. A repo with no releases yet installs from main.

  Installs what the ref's manifest.lua lists: programs into /home/bin, modules into /home/lib/lens and
  lens-hub.example.cfg into /home. /home/lens-hub.cfg is never touched. Every download is syntax-checked
  before any installed file is replaced, so a failed download can't break a computer.

  This file must stay self-contained (no lens.* modules): it's what installs them. Adapted from prism-update.
]]

local component  = require("component")
local filesystem = require("filesystem")
local serialization = require("serialization")

local VERSION = "0.3.0"

local PREFIX   = os.getenv("LENS_PREFIX") or ""   -- lets the test suite install into a temp dir
local HOME     = PREFIX .. "/home"
local SETTINGS = PREFIX .. "/home/.lens-update.cfg"

local DEFAULT_REPO = "aharabedian/lens"
local USAGE = [[
usage: lens-update [OWNER/REPO] [latest | BRANCH | TAG]
  lens-update                  update from the saved source (first time: latest release of ]] .. DEFAULT_REPO .. [[)
  lens-update latest           follow releases (the default)
  lens-update main             follow the main branch (newest, may be unfinished)
  lens-update v0.3.0           install that release and stay on it
  lens-update OWNER/REPO [REF] use a fork: its latest release, or a branch/tag
The choice is saved for next time.]]

local PATH_PATTERN = "^[%w%-_./]+$"

local function fail(msg) io.stderr:write("lens-update: " .. msg .. "\n"); os.exit(1) end

local function readSettings()
  local f = io.open(SETTINGS, "r")
  if not f then return {} end
  local data = f:read("*a")
  f:close()
  return serialization.unserialize(data) or {}
end

local function writeFile(path, data)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  f:write(data)
  f:close()
  return true
end

-- Returns the body, or nil, reason, HTTP status (when the server answered).
local function fetch(url, headers)
  local internet = require("internet")
  local ok, handle = pcall(internet.request, url, nil, headers)
  if not ok then return nil, tostring(handle) end
  local parts = {}
  local okRead, err = pcall(function() for chunk in handle do parts[#parts + 1] = chunk end end)
  if not okRead then
    -- An HTTP error makes the read throw; the handle's response() has the status code.
    local okCode, status = pcall(function() return (handle.response()) end)
    status = okCode and tonumber(status) or nil
    return nil, status and ("HTTP " .. status) or tostring(err), status
  end
  local data = table.concat(parts)
  if data == "" then return nil, "empty response" end
  return data
end

-- The tag of the repo's latest release; nil, "none" if it has no releases; nil, reason on failure.
local function latestRelease(repo)
  local url = ("https://api.github.com/repos/%s/releases/latest"):format(repo)
  local data, err, status = fetch(url, { ["User-Agent"] = "lens-update", Accept = "application/vnd.github+json" })
  if not data then
    if status == 404 then return nil, "none" end
    return nil, err
  end
  local tag = data:match('"tag_name"%s*:%s*"([^"]+)"')
  if not tag then return nil, "no tag_name in GitHub's answer" end
  return tag
end

---------------------------------------------------------------- main

if not component.isAvailable("internet") then fail("needs an Internet Card") end

local args = { ... }
if args[1] == "-h" or args[1] == "--help" or args[1] == "help" then print(USAGE); return end

local function usage(msg) fail(msg .. "\n" .. USAGE) end
local REPO_PATTERN, REF_PATTERN = "^[%w%-_.]+/[%w%-_.]+$", "^[%w%-_./]+$"

local settings = readSettings()
local repo, ref
if args[1] and args[1]:find("/", 1, true) then
  if not args[1]:match(REPO_PATTERN) then usage("not a GitHub repo: " .. args[1]) end
  repo, ref = args[1], args[2] or "latest"
elseif args[1] then
  if args[2] then usage("too many arguments") end
  ref = args[1]
end
repo = repo or settings.repo or DEFAULT_REPO
ref = ref or settings.ref or "latest"
if not repo:match(REPO_PATTERN) then usage("not a GitHub repo: " .. repo) end
if not ref:match(REF_PATTERN) or ref:find("..", 1, true) then usage("not a branch or tag: " .. ref) end

local source, what = ref, ref
if ref == "latest" then
  local tag, err = latestRelease(repo)
  if tag then
    source, what = tag, "latest release " .. tag
  elseif err == "none" then
    source, what = "main", "main (no releases yet)"
  else
    fail(("can't find the latest release of %s: %s\n  (lens-update main installs from the main branch instead)"):format(repo, err))
  end
end

local base = ("https://raw.githubusercontent.com/%s/%s/"):format(repo, source)
print(("lens-update %s: %s, %s"):format(VERSION, repo, what))

local files
do
  local data, err = fetch(base .. "manifest.lua")
  if not data then fail(("can't download manifest.lua from %s@%s: %s"):format(repo, source, err)) end
  local chunk = load(data, "=manifest.lua", "t", {})
  local ok, list = pcall(chunk or error)
  if not ok or type(list) ~= "table" or #list == 0 then fail("manifest.lua doesn't look right (wrong repo or branch?)") end
  for _, f in ipairs(list) do
    if type(f[1]) ~= "string" or type(f[2]) ~= "string" or not f[1]:match(PATH_PATTERN) or not f[2]:match(PATH_PATTERN)
       or f[1]:find("..", 1, true) or f[2]:find("..", 1, true) then
      fail("manifest.lua has a bad entry: " .. tostring(f[1]) .. " -> " .. tostring(f[2]))
    end
  end
  files = list
end

-- Download everything first; only replace installed files once all downloads look right.
local downloads = {}
for _, f in ipairs(files) do
  local data, err = fetch(base .. f[1])
  if not data then fail(("can't download %s from %s@%s: %s"):format(f[1], repo, source, err)) end
  local chunk, syntax = load(data, "=" .. f[1], "t", {})   -- the example config is Lua too
  if not chunk then fail(("%s doesn't look like valid Lua (wrong repo or branch?): %s"):format(f[1], syntax)) end
  downloads[#downloads + 1] = { path = HOME .. "/" .. f[2], data = data, name = f[1] }
end

local function makeDirs(dir)
  local path = ""
  for part in dir:gmatch("[^/]+") do
    path = path .. "/" .. part
    if not filesystem.exists(path) then filesystem.makeDirectory(path) end
  end
end

for _, d in ipairs(downloads) do makeDirs(d.path:match("^(.*)/[^/]*$")) end
for _, d in ipairs(downloads) do
  local tmp = d.path .. ".new"
  local ok, err = writeFile(tmp, d.data)
  if not ok then fail(("can't write %s: %s"):format(tmp, tostring(err))) end
  if filesystem.exists(d.path) then filesystem.remove(d.path) end
  filesystem.rename(tmp, d.path)
  print("  installed " .. d.path)
end

writeFile(SETTINGS, serialization.serialize({ repo = repo, ref = ref }))
local installed
for _, d in ipairs(downloads) do
  installed = installed or (d.name == "lib/lens/version.lua" and d.data:match('return%s*"([^"]+)"')) or nil
end
print(("done - LENS %s installed; restart lens-hub to use it"):format(installed or "?"))
if not filesystem.exists(HOME .. "/lens-hub.cfg") then
  print("  no /home/lens-hub.cfg yet: run lens-setup to make one (lens-hub also runs without it)")
end
if ref ~= "latest" then print(("  staying on %s; lens-update latest goes back to releases"):format(ref)) end
