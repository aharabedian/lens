--[[ tests/mocks/net.lua - a simulated OpenComputers network: several computers' modems in one test.

  local net = require("net").new{ maxPacketSize = 8192 }
  local modem = net:endpoint("addr-1")    a modem component: called with dots, like a component proxy
    modem.address, modem.isWireless(), modem.maxPacketSize()
    modem.open(port) -> bool (false if already open), modem.close(port), modem.isOpen(port)
    modem.broadcast(port, ...) / modem.send(address, port, ...) -> true
  modem.inbox                              queued { "modem_message", localAddress, remoteAddress, port, distance, ... }
  net.pop(modem) -> event | nil            take the oldest queued event
  net.drop = function(packet) return true end   lose packets (packet = { from, to, port, data })
  net.sent                                 every packet sent, delivered or not

  Delivery is immediate, to every other endpoint with the port open (send: only the named one).
  Packet limits follow our reading of OpenComputers' Network.Packet; marked unverified in docs/architecture.md:
    at most 8 values; size = sum of: string -> its length (min 1), number -> 8, boolean / nil -> 4;
    size over maxPacketSize raises "packet too big (max N)".
]]

local net = {}

local MAX_PARTS = 8

local function packetSize(data)
  local size = 0
  for i = 1, data.n do
    local v = data[i]
    local t = type(v)
    if t == "string" then size = size + math.max(1, #v)
    elseif t == "number" then size = size + 8
    elseif t == "boolean" or t == "nil" then size = size + 4
    else error("unsupported data type: " .. t, 3) end
  end
  return size
end

function net.new(opts)
  opts = opts or {}
  local self = { endpoints = {}, sent = {}, drop = nil, maxPacketSize = opts.maxPacketSize or 8192 }

  local function deliver(from, to, port, data)
    local packet = { from = from.address, to = to, port = port, data = data }
    if data.n > MAX_PARTS then error("packet has too many parts", 3) end
    local size = packetSize(data)
    if size > self.maxPacketSize then error(("packet too big (max %d)"):format(self.maxPacketSize), 3) end
    self.sent[#self.sent + 1] = packet
    if self.drop and self.drop(packet) then return end
    for _, ep in ipairs(self.endpoints) do
      if ep ~= from and ep.ports[port] and (to == nil or to == ep.address) then
        local ev = { "modem_message", ep.address, from.address, port, 0 }
        for i = 1, data.n do ev[5 + i] = data[i] end
        ev.n = 5 + data.n
        ep.inbox[#ep.inbox + 1] = ev
      end
    end
  end

  function self.endpoint(_, address)
    local ep = { address = address or ("modem-" .. (#self.endpoints + 1)), ports = {}, inbox = {} }
    ep.isWireless = function() return true end
    ep.maxPacketSize = function() return self.maxPacketSize end
    ep.open = function(port)
      if ep.ports[port] then return false end
      ep.ports[port] = true
      return true
    end
    ep.close = function(port) ep.ports[port] = nil; return true end
    ep.isOpen = function(port) return ep.ports[port] == true end
    ep.broadcast = function(port, ...)
      deliver(ep, nil, port, table.pack(...))
      return true
    end
    ep.send = function(to, port, ...)
      deliver(ep, to, port, table.pack(...))
      return true
    end
    self.endpoints[#self.endpoints + 1] = ep
    return ep
  end

  function self.pop(ep) return table.remove(ep.inbox, 1) end

  return self
end

return net
