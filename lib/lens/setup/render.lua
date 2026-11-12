--[[ lens.setup.render: lens-hub.cfg as Lua source, with a comment on each setting.

  hub(c) -> text     c: the config as it should be saved (lens-setup's answers on top of the old file).
                     Settings first, then panels, hud and rules; keys it doesn't know are kept at the end.
  lua(v) -> text     any plain value as Lua source: keys in a stable order, queries in single quotes
]]

local VERSION = require("lens.version")

local R = {}

-- Strings with double quotes (queries) read better in single quotes.
local function str(s)
  if s:find('"', 1, true) and not s:find("['\\\n]") then return "'" .. s .. "'" end
  return ("%q"):format(s)
end

local ORDER = { "id", "anchor", "x", "y", "width", "kind", "label", "level", "text", "value", "when", "of", "max",
  "percent", "unit", "format", "color", "warnAbove", "badAbove", "warnBelow", "badBelow", "values", "status", "dots",
  "by", "states", "for", "count" }
local RANK = {}
for i, k in ipairs(ORDER) do RANK[k] = i end

local function keyRef(k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") and k ~= "for" then return k end
  return "[" .. R.lua(k) .. "]"
end

function R.lua(v)
  local t = type(v)
  if t == "string" then return str(v) end
  if t ~= "table" then return tostring(v) end
  local parts, n = {}, #v
  for i = 1, n do parts[#parts + 1] = R.lua(v[i]) end
  local keys = {}
  for k in pairs(v) do
    if not (math.type(k) == "integer" and k >= 1 and k <= n) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b)
    local ra, rb = RANK[a] or 100, RANK[b] or 100
    if ra ~= rb then return ra < rb end
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(keys) do parts[#parts + 1] = keyRef(k) .. " = " .. R.lua(v[k]) end
  if #parts == 0 then return "{}" end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local SETTINGS = {
  { "node", "this hub's name" },
  { "port", "the LENS port: every agent's lensPort (not PRISM's control port)" },
  { "token", "shared secret: every agent's lensToken; nil = none" },
  { "staleAfter", "missed snapshots before a node counts as stopped reporting" },
  { "beep", "beep when a new bad alert appears" },
  { "sample", "seconds between the panels' sparkline samples" },
  { "nonCritical", "agents whose silence is only a warning" },
}

local function list(L, name, items, comment)
  L[#L + 1] = ""
  if comment then L[#L + 1] = "  -- " .. comment end
  if #items == 0 then L[#L + 1] = ("  %s = {},"):format(name); return end
  L[#L + 1] = ("  %s = {"):format(name)
  for _, item in ipairs(items) do L[#L + 1] = "    " .. R.lua(item) .. "," end
  L[#L + 1] = "  },"
end

function R.hub(c)
  local L = {
    "-- lens-hub.cfg - written by lens-setup " .. VERSION .. ". Run lens-setup to change it; values you edit",
    "-- by hand are kept when it rewrites this file (comments aren't). Every option: docs/hub.md",
    "return {",
  }
  local known = { panels = true, hud = true, rules = true }
  for _, s in ipairs(SETTINGS) do
    known[s[1]] = true
    local v = c[s[1]]
    local line = ("  %s = %s,"):format(s[1], v == nil and "nil" or R.lua(v))
    L[#L + 1] = ("%-40s -- %s"):format(line, s[2])
  end
  list(L, "panels", c.panels or {}, "the views the dashboard starts with: docs/views.md")

  L[#L + 1] = ""
  L[#L + 1] = "  -- everyone's default AR glasses HUD (Glasses Terminals on this computer): docs/hud.md; false = off"
  if c.hud == false then
    L[#L + 1] = "  hud = false,"
  else
    local hud = {}
    for k, v in pairs(c.hud or {}) do if k ~= "bars" and k ~= "blocks" then hud[k] = v end end
    local head = R.lua(hud)
    L[#L + 1] = "  hud = " .. head:sub(1, -3) .. (head == "{}" and "{" or ",")
    local bars = (c.hud or {}).bars
    if bars then                                -- an old one-corner hud, kept as it was
      L[#L + 1] = "    bars = {"
      for _, b in ipairs(bars) do L[#L + 1] = "      " .. R.lua(b) .. "," end
      L[#L + 1] = "    },"
    end
    L[#L + 1] = "    blocks = {"
    for _, b in ipairs((c.hud or {}).blocks or {}) do
      local blk = {}
      for k, v in pairs(b) do if k ~= "elements" then blk[k] = v end end
      local bh = R.lua(blk)
      L[#L + 1] = "      " .. bh:sub(1, -3) .. (bh == "{}" and "{" or ",") .. " elements = {"
      for _, el in ipairs(b.elements or {}) do
        local line = R.lua(el)
        if el.status and #line > 110 then              -- long: a rule per line
          local rest = {}
          for k, v in pairs(el) do if k ~= "status" then rest[k] = v end end
          L[#L + 1] = "        " .. R.lua(rest):sub(1, -3) .. ", status = {"
          for _, r in ipairs(el.status) do L[#L + 1] = "          " .. R.lua(r) .. "," end
          L[#L + 1] = "        } },"
        else
          L[#L + 1] = "        " .. line .. ","
        end
      end
      L[#L + 1] = "      } },"
    end
    L[#L + 1] = "    },"
    L[#L + 1] = "  },"
  end

  list(L, "rules", c.rules or {}, "the hub's own alerts: docs/hub.md#rules")

  local extra = {}
  for k in pairs(c) do if not known[k] then extra[#extra + 1] = k end end
  table.sort(extra, function(a, b) return tostring(a) < tostring(b) end)
  if #extra > 0 then L[#L + 1] = "" end
  for _, k in ipairs(extra) do L[#L + 1] = ("  %s = %s,"):format(keyRef(k), R.lua(c[k])) end
  L[#L + 1] = "}"
  return table.concat(L, "\n") .. "\n"
end

return R
