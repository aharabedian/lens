--[[ tests/mocks/oc.lua - the parts of OpenComputers / OpenOS the tests need, as `require`-able modules.

  local M = require("oc")
  M.serialization        serialize / unserialize, round-tripping like OpenOS (non-pretty mode)
  M.time                 what computer.uptime() returns; tests move it forward
  M.setTime(t)

  Grows as the programs need more of the game (network, screens, glasses), and only with behavior
  we've confirmed in game or marked as an assumption in docs/architecture.md.
]]

local M = { time = 0 }

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

---------------------------------------------------------------- computer
M.computer = { uptime = function() return M.time end }
function M.setTime(t) M.time = t end

package.preload.serialization = function() return M.serialization end
package.preload.computer = function() return M.computer end

return M
