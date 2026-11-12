--[[ lens-hub.lua - the LENS hub: hears every agent in the base (PRISM routers, ...) and shows the whole
  base on one screen: nodes, alerts and the panels set in /home/lens-hub.cfg.

  Needs a GPU and screen (tier 3 for the full layout; tier 2 works) and a network card. With an OC Glasses
  Glasses Terminal attached, it also draws a small HUD in the glasses linked to it.
  Usage: lens-hub [path]    (default /home/lens-hub.cfg; optional - see docs/hub.md)
  Tap an alert to acknowledge it; QUIT or Ctrl+C to stop. The work is in /home/lib/lens/hub/.
]]

-- Modules live in /home/lib/lens (lens-update installs them). Forget copies cached by an earlier
-- run, so restarting after an update loads the new ones.
if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lens%.") then package.loaded[name] = nil end end
if not pcall(require, "lens.version") then error("LENS's modules are missing from /home/lib/lens - run lens-update", 0) end

local component = require("component")
local computer  = require("computer")
local event     = require("event")
local term      = require("term")
local config    = require("lens.hub.config")
local App       = require("lens.hub.app")

local path = ({ ... })[1] or "/home/lens-hub.cfg"
local cfg, err = config.load(path)
if not cfg then error(path .. ": " .. tostring(err), 0) end

if not component.isAvailable("modem") then error("lens-hub needs a network card (wireless, or wired to the agents)", 0) end
local gpu = component.gpu
local w, h = gpu.maxResolution()
local glasses = component.isAvailable("glasses") and component.glasses or nil
local app, why = App.new(cfg, { gpu = gpu, w = w, h = h, modem = component.modem, glasses = glasses,
  beep = computer.beep })
if not app then error(path .. ": " .. tostring(why), 0) end

local function main()
  app:start(computer.uptime())
  local nextTick = computer.uptime() + 1
  while app.running do
    local ev = table.pack(event.pullMultiple(math.max(0.05, nextTick - computer.uptime()),
      "modem_message", "touch", "interrupted"))
    local now = computer.uptime()
    if ev[1] == "modem_message" then
      -- modem_message: localAddress, remoteAddress, port, distance, payload
      app:onModem(ev[3], ev[4], ev[6], now)
    elseif ev[1] == "touch" then
      -- touch: screenAddress, x, y, button, player
      app:onTouch(math.floor(ev[3]), math.floor(ev[4]), now)
    elseif ev[1] == "interrupted" then
      app.running = false
    end
    if app.running and now >= nextTick then
      app:tick(now)
      nextTick = now + 1
    end
  end
end

local ok, failure = xpcall(main, debug.traceback)
app:stop()
term.clear()
if not ok then io.stderr:write(tostring(failure) .. "\n") end
