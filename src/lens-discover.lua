--[[ lens-discover.lua - list this computer's components with every method and its documentation, to design
  LENS agents and the HUD against the real API of a mod (AR glasses, GT energy, IC2 reactors...).

  Usage:
    lens-discover [text] [--all]   components; methods of those whose type contains `text`
                                   (--all: also the basics every computer has: gpu, screen, filesystem...)
    lens-discover --widgets [type] create one of each widget on a glasses-like component (default type:
                                   glasses), list what each widget object offers, and remove it again
    lens-discover --events [secs]  print every event for secs seconds (default 30): put glasses on, click...
  Everything is also written to /home/lens-discover.txt (on your own machine:
  saves/<world>/opencomputers/<disk address>/home/lens-discover.txt).
]]

if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lens%.") then package.loaded[name] = nil end end
if not pcall(require, "lens.version") then error("LENS's modules are missing from /home/lib/lens - run lens-update", 0) end

local component = require("component")
local computer  = require("computer")
local event     = require("event")
local discover  = require("lens.discover")
local VERSION   = require("lens.version")

local args = { ... }
local opts, mode, arg2 = {}, "report", nil
for i, a in ipairs(args) do
  if a == "--all" then opts.all = true
  elseif a == "--widgets" or a == "--events" then mode, arg2 = a:sub(3), args[i + 1]
  elseif mode == "report" then opts.filter = a end
end

local out = (os.getenv("LENS_PREFIX") or "") .. "/home/lens-discover.txt"
local lines, shown = { "lens-discover " .. VERSION, "" }, {}
print("lens-discover " .. VERSION)

if mode == "report" then
  local report, summary = discover.report(component, opts)
  for _, l in ipairs(summary) do print("  " .. l); lines[#lines + 1] = l end
  lines[#lines + 1] = ""
  for _, l in ipairs(report) do lines[#lines + 1] = l end
elseif mode == "widgets" then
  local ctype = arg2 or "glasses"
  local addr = component.list(ctype, true)()
  if not addr then error("no " .. ctype .. " component found (is the Glasses Terminal attached?)", 0) end
  for _, l in ipairs(discover.widgets(component.proxy(addr))) do shown[#shown + 1] = l; lines[#lines + 1] = l end
  for _, l in ipairs(shown) do print(l) end
elseif mode == "events" then
  local secs = tonumber(arg2) or 30
  print(("printing every event for %d s - Ctrl+C to stop sooner"):format(secs))
  local stop = computer.uptime() + secs
  while computer.uptime() < stop do
    local ev = table.pack(event.pull(stop - computer.uptime()))
    if ev[1] == "interrupted" then break end
    if ev[1] then
      local l = ("%7.1f  %s"):format(computer.uptime(), discover.event(ev))
      print(l)
      lines[#lines + 1] = l
    end
  end
end

local f, err = io.open(out, "w")
if not f then error("can't write " .. out .. ": " .. tostring(err), 0) end
f:write(table.concat(lines, "\n"), "\n")
f:close()
print(("written to %s"):format(out))
