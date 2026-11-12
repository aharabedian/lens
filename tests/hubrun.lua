--[[ tests/hubrun.lua - lens-hub end to end for feature tests: agents on mocks/net.lua, Glasses Terminals, a
  keyboard, and a script of events, until the script stops it. (test_dashboard and test_net keep their own
  agents: they test the protocol itself.)

  local R = require("hubrun")(H)     H: the test's helper (its TMP directory and H.run)
  local a = R.agent{ node = "power-room", role = "lumen", setup = function(m) ... end, cycle = function(m, now) end }
    setup(m) once (declare and set metrics on m, a lens.metrics registry); cycle(m, now) before every push.
    It sends a describe and a snapshot every 5 s, and answers the hub's hello.
  local ok, err, dir = R.run{ cfg = "return { ... }", dir = "name", agents = { a, ... },
                              terminals = { [address] = glasses mock }, keyboard = true,
                              script = function(t) -> event | nil | "stop" }
    Writes cfg to TMP/<dir>/lens-hub.cfg (a fresh directory; lens-board.cfg appears next to it) and runs
    lens-hub on it. script is asked for an event on every pull once the queue is empty: an event table, nil to
    let time pass, or "stop". Anything lens-hub writes to stderr counts as a failure.
  R.tap(text, player?, minY?, minX?) -> a touch event on the first place showing text (one column in)
  R.key(code, player) / R.keys(text, player) -> key_down event(s); R.paste(text, player) -> a clipboard event
                      (R.keys returns several values: keep it last in an argument list, or Lua keeps only one)
  R.queue(event...)   events delivered, in order, before the script is asked again
]]

local M = require("oc")
local net = require("net")
local codec = require("lens.codec")
local metrics = require("lens.metrics")

local PORT = 4243

local R = {}
local H                 -- the test's helper, given when the module is used
local queued = {}

function R.agent(o)
  local m = metrics.new{ role = o.role, clock = function() return M.time end }
  if o.setup then o.setup(m) end
  return { node = o.node, role = o.role, m = m, cycle = o.cycle,
    enc = codec.encoder{ node = o.node, role = o.role, boot = 3, interval = 5 } }
end

function R.queue(...) for _, e in ipairs({ ... }) do queued[#queued + 1] = e end end

function R.tap(text, player, minY, minX)
  local x, y = M.find(text, minY, minX)
  assert(x, "nothing on screen says " .. text)
  return { "touch", "screen", x + 1, y, 0, player or "p" }
end

function R.key(code, player) return { "key_down", "kb000000", 0, code, player } end

function R.keys(text, player)
  local out = {}
  for _, c in utf8.codes(text) do out[#out + 1] = { "key_down", "kb000000", c, 0, player } end
  return table.unpack(out)
end

function R.paste(text, player) return { "clipboard", "kb000000", text, player } end

function R.run(o)
  M.components = {}
  if o.keyboard then M.components["kb000000"] = { type = "keyboard", methods = {} } end
  for addr, G in pairs(o.terminals or {}) do M.components[addr] = { type = "glasses", proxy = G.proxy, methods = {} } end
  local dir = H.TMP .. "/" .. (o.dir or "hub")
  os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
  local f = assert(io.open(dir .. "/lens-hub.cfg", "w"))
  f:write(o.cfg or "return {}")
  f:close()

  local n = net.new()
  M.modem = n:endpoint("hub")
  local agents = {}
  for _, a in ipairs(o.agents or {}) do
    a.ep = n:endpoint(a.node)
    a.ep.open(PORT)
    agents[#agents + 1] = a
  end
  local function push(a, describe)
    if a.cycle then a.cycle(a.m, M.time) end
    if describe then for _, p in ipairs(a.enc:describe(a.m:describe())) do a.ep.broadcast(PORT, p) end end
    for _, p in ipairs(a.enc:snapshot(a.m:snapshot())) do a.ep.broadcast(PORT, p) end
  end
  local nextPush = 0
  queued = {}
  M.onPull = function()
    for _, a in ipairs(agents) do
      local ev = n.pop(a.ep)
      while ev do
        local msg = codec.decode(ev[6])
        if msg and msg.kind == "hello" then push(a, true) end
        ev = n.pop(a.ep)
      end
    end
    if M.time >= nextPush then
      for _, a in ipairs(agents) do push(a, true) end
      nextPush = M.time + 5
    end
    local ev = n.pop(M.modem)
    if ev then return ev end
    if #queued > 0 then return table.remove(queued, 1) end
    local e = o.script(M.time)
    if e == "stop" then return { "interrupted" } end
    return e
  end
  local realStderr, written = io.stderr, {}
  io.stderr = { write = function(_, ...) for _, s in ipairs({ ... }) do written[#written + 1] = tostring(s) end end }
  local ok, err = pcall(H.run, "lens-hub.lua", dir .. "/lens-hub.cfg")
  io.stderr = realStderr
  M.onPull = nil
  M.components = {}
  M.modem = nil
  if ok and #written > 0 then return false, table.concat(written), dir end
  return ok, err, dir
end

return function(helper)
  H = helper
  return R
end
