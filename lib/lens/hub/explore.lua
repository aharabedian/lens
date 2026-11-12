--[[ lens.hub.explore: building a query by tapping: a metric, label filters, how to combine its series.
  Pure.

  explore.FUNCS                      "sum", "max", "min", "avg", "count", "rate" (the order the screen shows)
  explore.query(metric, filters, fn) -> text
    metric: a name; filters: { [label] = value } (only these series); fn: one of FUNCS.
    sum(lumen_net_5m_eut{lsc="Main"}); labels sorted; values quoted with \ and " escaped.
  explore.labels(series, filters) -> { { label, values = { value... }, chosen = value | nil }... }
    every label the metric's series have (node first, then by name), each with its values sorted; values of
    the series the other filters still match, so choosing narrows the rest
  explore.matches(series, filters) -> bool
  explore.labelText(labels) -> "node=power-room lsc=Main"   (node first)
  explore.suggestLabel(metric, filters) -> "net 5m eut · Main"   a starting label for a view
]]

local explore = {}

explore.FUNCS = { "sum", "max", "min", "avg", "count", "rate" }

local function quote(v) return '"' .. tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if a == "node" or b == "node" then return a == "node" and b ~= "node" end
    return a < b
  end)
  return keys
end

function explore.query(metric, filters, fn)
  local parts = {}
  for _, k in ipairs(sortedKeys(filters or {})) do parts[#parts + 1] = k .. "=" .. quote(filters[k]) end
  local sel = metric .. (#parts > 0 and ("{" .. table.concat(parts, ", ") .. "}") or "")
  return (fn or "sum") .. "(" .. sel .. ")"
end

function explore.matches(s, filters, except)
  for k, v in pairs(filters or {}) do
    if k ~= except and (s.labels or {})[k] ~= v then return false end
  end
  return true
end

function explore.labels(series, filters)
  filters = filters or {}
  local values = {}
  for _, s in ipairs(series) do
    for k in pairs(s.labels or {}) do values[k] = values[k] or {} end
  end
  local out = {}
  for _, k in ipairs(sortedKeys(values)) do
    local set, list = {}, {}
    for _, s in ipairs(series) do
      local v = (s.labels or {})[k]
      if v and not set[v] and explore.matches(s, filters, k) then set[v] = true; list[#list + 1] = v end
    end
    table.sort(list)
    out[#out + 1] = { label = k, values = list, chosen = filters[k] }
  end
  return out
end

function explore.labelText(labels)
  local parts = {}
  for _, k in ipairs(sortedKeys(labels or {})) do parts[#parts + 1] = k .. "=" .. tostring(labels[k]) end
  return table.concat(parts, " ")
end

function explore.suggestLabel(metric, filters)
  local base = metric:gsub("^[%l%d]+_", "", 1):gsub("_", " ")
  local extra = {}
  for _, k in ipairs(sortedKeys(filters or {})) do
    if k ~= "node" then extra[#extra + 1] = filters[k] end
  end
  if #extra > 0 then base = base .. " · " .. table.concat(extra, " ") end
  return base
end

return explore
