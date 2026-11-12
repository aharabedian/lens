--[[ lens-setup.lua - guided setup for the LENS hub: writes /home/lens-hub.cfg.

  Usage: lens-setup

  Asks for the hub's name, port and secret; says hello on the network and offers standard panels for each
  PRISM router that answers; sets up the AR glasses HUD when a Glasses Terminal is attached; and can start
  lens-hub on boot (through /home/.shrc). Shows the file before saving it, and keeps the old one as
  lens-hub.cfg.bak.

  Run it again any time: current settings are the defaults (Enter keeps one), panels and HUD bars you have
  are kept, and only new agents are offered. Settings it doesn't ask about are kept. Ctrl+D cancels.
  The steps live in /home/lib/lens/setup/.
]]

if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lens%.") then package.loaded[name] = nil end end
if not pcall(require, "lens.version") then error("LENS's modules are missing from /home/lib/lens - run lens-update", 0) end

local component = require("component")
local VERSION   = require("lens.version")
local input     = require("lens.setup.input")
local hub       = require("lens.setup.hub")

local home = (os.getenv("LENS_PREFIX") or "") .. "/home"
print("lens-setup " .. VERSION .. " - Enter keeps the [default], Ctrl+D cancels")
local ok, err = pcall(hub.run, {
  cfgPath = home .. "/lens-hub.cfg",
  shrcPath = home .. "/.shrc",
  modem = component.isAvailable("modem") and component.modem or nil,
  glasses = component.isAvailable("glasses"),
})
if not ok then
  if err == input.CANCEL then print(""); print("cancelled - nothing saved")
  else error(err, 0) end
end
