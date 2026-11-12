--[[ tests/mocks/oc.lua - the parts of OpenComputers / OpenOS the tests need, as `require`-able modules
  (component, computer, event, serialization, unicode, term, filesystem, internet).

  local M = require("oc")
  M.serialization        serialize / unserialize, round-tripping like OpenOS (non-pretty mode)
  M.time                 what computer.uptime() returns; M.setTime(t)
  M.onPull(n)            called on every event.pullMultiple; return an event table to deliver it, or nil
                         to let time pass: pullMultiple(timeout) with no event moves M.time by `timeout`
  M.modem                the modem component.modem returns (set it to a mocks/net.lua endpoint)
  M.components[addr] = { type, methods = { [name] = doc string }, proxy? }
                         components for component.list / type / methods / doc / proxy (lens-discover)
  M.resize(w, h)         a blank w x h screen (160x50 = tier 3, 80x25 = tier 2)
  M.row(y), M.find(text, minY, minX), M.dump(path)   read what the GPU drew
  M.fgAt(x, y), M.bgAt(x, y)
  M.gpuCalls             set + fill calls so far
  M.beeps, M.cleared
  M.web[url] = text      served by internet.request (missing -> 404, { status = N } -> HTTP N)
  M.requests             every internet request: { url, headers }

  Grows as the programs need more of the game, and only with behavior we've confirmed in game or marked
  as an assumption in docs/architecture.md. Modelled on PRISM's mock (tests/mocks/oc.lua there).
]]

local M = { time = 0, pulls = 0, beeps = 0, gpuCalls = 0, web = {}, requests = {} }

---------------------------------------------------------------- serialization
-- Keys always as ["key"]= / [n]=, so sizes are a little larger than OpenOS's (which writes key= and
-- leaves array indices implicit). Erring large keeps the tests' packet-size checks on the safe side.
local function ser(v)
  local t = type(v)
  if t == "table" then
    local parts = {}
    for k, x in pairs(v) do
      local ks = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
      parts[#parts + 1] = ks .. "=" .. ser(x)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return string.format("%q", v)
  else
    return tostring(v)
  end
end

M.serialization = {
  serialize = ser,
  unserialize = function(s)
    local f = load("return " .. s, "=ser", "t", {})
    if not f then return nil end
    local ok, r = pcall(f)
    return ok and r or nil
  end,
}

---------------------------------------------------------------- math.random
-- In game, math.random(1, 0x7fffffff) gave PRISM a number that wasn't an integer (math.type ~= "integer",
-- 2026-11-12). Mirror that: every result is a float, whole-valued for (m) and (m, n).
local realRandom = math.random
math.random = function(m, n) -- luacheck: ignore 122
  if m == nil then return realRandom() end
  return realRandom(m, n or m) + 0.0
end

---------------------------------------------------------------- computer, event
M.computer = {
  uptime = function() return M.time end,
  beep = function() M.beeps = M.beeps + 1 end,
}
function M.setTime(t) M.time = t end

local function pull(timeout)
  M.pulls = M.pulls + 1
  if M.onPull then
    local ev = M.onPull(M.pulls)
    if ev then return table.unpack(ev, 1, ev.n or #ev) end
  end
  M.time = M.time + (timeout or 0)
  return nil
end
local event = {
  pullMultiple = function(timeout) return pull(timeout) end,
  pull = function(timeout) return pull(timeout) end,
}

---------------------------------------------------------------- GPU + screen
local GW, GH, buf, fgb, bgb
function M.resize(w, h)
  GW, GH = w, h
  M.W, M.H = GW, GH
  buf, fgb, bgb = {}, {}, {}
  for y = 1, GH do
    buf[y], fgb[y], bgb[y] = {}, {}, {}
    for x = 1, GW do buf[y][x], fgb[y][x], bgb[y][x] = " ", 0xffffff, 0 end
  end
end
M.resize(160, 50)
M.oob = 0
local cf, cb = 0xffffff, 0
local function cell(x, y, ch)
  if x >= 1 and x <= GW and y >= 1 and y <= GH then
    buf[y][x], fgb[y][x], bgb[y][x] = ch, cf, cb
  else
    M.oob = M.oob + 1
    M.oobAt = M.oobAt or (x .. "," .. y .. " '" .. ch .. "'")
  end
end
local gpu = {
  address = "gp000000", type = "gpu",
  maxResolution = function() return GW, GH end,
  setResolution = function() return true end,
  setForeground = function(c) local o = cf; cf = c; return o end,
  setBackground = function(c) local o = cb; cb = c; return o end,
  set = function(x, y, s)
    assert(type(s) == "string", "gpu.set needs a string")
    M.gpuCalls = M.gpuCalls + 1
    local i = 0
    for _, cp in utf8.codes(s) do cell(x + i, y, utf8.char(cp)); i = i + 1 end
    return true
  end,
  fill = function(x, y, w, h, ch)
    assert(utf8.len(ch) == 1, "fill char must be 1 char")
    M.gpuCalls = M.gpuCalls + 1
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do cell(xx, yy, ch) end end
    return true
  end,
}

function M.row(y) return table.concat(buf[y]) end
function M.fgAt(x, y) return fgb[y][x] end
function M.bgAt(x, y) return bgb[y][x] end

-- First occurrence of `text` (plain) at or below row minY, at or right of column minX -> x, y.
function M.find(text, minY, minX)
  minX = minX or 1
  for y = minY or 1, GH do
    local r = table.concat(buf[y], "", minX)
    local i = r:find(text, 1, true)
    if i then return utf8.len(r:sub(1, i - 1)) + minX, y end
  end
end

-- A "size<TAB>W<TAB>H" line, then one "char<TAB>fg<TAB>bg" line per cell; tools/render_screens.py
-- turns it into a PNG.
function M.dump(path)
  local f = assert(io.open(path, "w"))
  f:write(string.format("size\t%d\t%d\n", GW, GH))
  for y = 1, GH do
    for x = 1, GW do f:write(string.format("%s\t%06x\t%06x\n", buf[y][x], fgb[y][x], bgb[y][x])) end
  end
  f:close()
end

---------------------------------------------------------------- component
M.components = {}
local component = {
  gpu = gpu,
  -- Like OpenOS: a callable table address -> type; filter matches part of the type unless exact.
  list = function(filter, exact)
    local found, keys = {}, {}
    for addr, c in pairs(M.components) do
      if not filter or (exact and c.type == filter) or (not exact and c.type:find(filter, 1, true)) then
        found[addr] = c.type
        keys[#keys + 1] = addr
      end
    end
    table.sort(keys)
    local i = 0
    return setmetatable(found, { __call = function()
      i = i + 1
      if keys[i] then return keys[i], found[keys[i]] end
    end })
  end,
  type = function(addr) return M.components[addr] and M.components[addr].type end,
  methods = function(addr)
    local c = M.components[addr]
    if not c then return nil, "no such component" end
    local out = {}
    for name in pairs(c.methods or {}) do out[name] = true end
    return out
  end,
  proxy = function(addr) local c = M.components[addr]; return c and c.proxy end,
  doc = function(addr, method)
    local c = M.components[addr]
    return c and c.methods and c.methods[method] or nil
  end,
  isAvailable = function(t)
    if t == "gpu" or t == "screen" then return true end
    if t == "modem" then return M.modem ~= nil end
    if t == "internet" then return M.internet ~= false end
    return false
  end,
}
setmetatable(component, { __index = function(_, k) if k == "modem" then return M.modem end end })

---------------------------------------------------------------- unicode, filesystem, internet
local unicode = {
  len = function(s) return utf8.len(s) end,
  sub = function(s, i, j)
    local n = utf8.len(s)
    j = j or n
    if i < 0 then i = n + i + 1 end
    if j < 0 then j = n + j + 1 end
    if i < 1 then i = 1 end
    if j > n then j = n end
    if i > j then return "" end
    local a, b = utf8.offset(s, i), utf8.offset(s, j + 1)
    return s:sub(a, b and b - 1 or #s)
  end,
}

local function sh(cmd) local ok = os.execute(cmd); return ok == true or ok == 0 end
local filesystem = {
  exists = function(p) return sh('test -e "' .. p .. '"') end,
  makeDirectory = function(p) return sh('mkdir -p "' .. p .. '"') end,
  remove = function(p) return os.remove(p) end,
  rename = function(a, b) return os.rename(a, b) end,
}

-- Like OpenOS internet.request: a callable handle that yields the body; reads of an HTTP error
-- throw (Java's message is the URL) and handle.response() gives code, message, headers.
local internet = {
  request = function(url, _, headers)
    M.requests[#M.requests + 1] = { url = url, headers = headers }
    local body = M.web[url]
    local status = body == nil and 404 or (type(body) == "table" and body.status) or 200
    local done = false
    return setmetatable({
      response = function() return status, status == 200 and "OK" or "Error", {} end,
      close = function() end,
    }, { __call = function()
      if status ~= 200 then error(url) end
      if done then return nil end
      done = true
      return body
    end })
  end,
}

package.preload.serialization = function() return M.serialization end
package.preload.computer      = function() return M.computer end
package.preload.event         = function() return event end
package.preload.component     = function() return component end
package.preload.unicode       = function() return unicode end
package.preload.term          = function() return { clear = function() M.cleared = true end } end
package.preload.filesystem    = function() return filesystem end
package.preload.internet      = function() return internet end

return M
