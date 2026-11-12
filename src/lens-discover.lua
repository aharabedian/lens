--[[ lens-discover.lua - list this computer's components with every method and its documentation, to design
  LENS agents and the HUD against the real API of a mod (AR glasses, GT energy, IC2 reactors...).

  Usage: lens-discover [text] [--all]
    text    only components whose type contains it (e.g. lens-discover glasses)
    --all   also detail the basics every computer has (gpu, screen, filesystem, ...)
  Prints the component list and writes the full report to /home/lens-discover.txt. On your own machine that
  file is at saves/<world>/opencomputers/<disk address>/home/lens-discover.txt.
]]

if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lens%.") then package.loaded[name] = nil end end
if not pcall(require, "lens.version") then error("LENS's modules are missing from /home/lib/lens - run lens-update", 0) end

local component = require("component")
local discover  = require("lens.discover")
local VERSION   = require("lens.version")

local opts = {}
for _, a in ipairs({ ... }) do
  if a == "--all" then opts.all = true else opts.filter = a end
end

local out = (os.getenv("LENS_PREFIX") or "") .. "/home/lens-discover.txt"
local lines, summary = discover.report(component, opts)
print("lens-discover " .. VERSION)
for _, l in ipairs(summary) do print("  " .. l) end
local f, err = io.open(out, "w")
if not f then error("can't write " .. out .. ": " .. tostring(err), 0) end
f:write("lens-discover " .. VERSION .. "\n\n", table.concat(summary, "\n"), "\n\n", table.concat(lines, "\n"), "\n")
f:close()
print(("methods and docs written to %s"):format(out))
