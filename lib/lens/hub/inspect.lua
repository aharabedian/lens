--[[ lens.hub.inspect: what a view's query comes to, for the panel page. Pure.

  inspect.parts(text) -> { "sum(x)"... }     the function calls in a query (sum, count, max, min, avg, rate of a
                                             selector), in order, each once
  inspect.substitute(text, values) -> text   each part replaced by its value's text (values: { [part] = text })
  inspect.metrics(text, names) -> { name... }   the metric names (from `names`) the query mentions, in order
  inspect.stats(history) -> { low, average, high, last, n } | nil   over the numbers in history (false: no data)
]]

local inspect = {}

local FUNCS = { sum = true, count = true, max = true, min = true, avg = true, rate = true }

function inspect.parts(text)
  local out, seen = {}, {}
  for name, args in tostring(text):gmatch("([%a_][%w_]*)%s*(%b())") do
    local part = name .. args
    if FUNCS[name] and not seen[part] then
      seen[part] = true
      out[#out + 1] = part
    end
  end
  return out
end

function inspect.substitute(text, values)
  local out = tostring(text)
  for part, value in pairs(values) do
    local i, j = out:find(part, 1, true)
    while i do
      out = out:sub(1, i - 1) .. value .. out:sub(j + 1)
      i, j = out:find(part, i + #value, true)
    end
  end
  return out
end

function inspect.metrics(text, names)
  local found = {}
  local t = tostring(text)
  for _, name in ipairs(names) do
    local at = 1
    while true do
      local i, j = t:find(name, at, true)
      if not i then break end
      local before, after = t:sub(i - 1, i - 1), t:sub(j + 1, j + 1)
      if not before:find("[%w_]") and not after:find("[%w_]") then
        found[#found + 1] = { i, name }
        break
      end
      at = j + 1
    end
  end
  table.sort(found, function(a, b) return a[1] < b[1] end)
  local out = {}
  for i, f in ipairs(found) do out[i] = f[2] end
  return out
end

function inspect.stats(history)
  local low, high, sum, n, last = math.huge, -math.huge, 0, 0, nil
  for _, v in ipairs(history or {}) do
    if type(v) == "number" then
      low, high, sum, n, last = math.min(low, v), math.max(high, v), sum + v, n + 1, v
    end
  end
  if n == 0 then return nil end
  return { low = low, high = high, average = sum / n, last = last, n = n }
end

return inspect
