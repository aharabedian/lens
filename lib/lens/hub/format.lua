--[[ lens.hub.format: a view's value as text, a bar fraction and a color level, the same on the dashboard and
  in the HUD. Pure.

  A view (a panel, a HUD bar or text): { label, value = query?, of = query?, max?, unit?,
    format = "auto" | "percent" | "duration" | "signed",   default "auto" ("percent": value is 0..1)
    color = "thresholds" | "sign" | "status" | "none",      how the value and bar are colored; default "thresholds"
    warnAbove?, badAbove?, warnBelow?, badBelow?,           (thresholds compare the value itself)
    text = "{stored} / {cap} EU"?, values = { stored = query, cap = query }?   several values in one line:
                                                            each {name} formatted with `format`; {value} and
                                                            {of} are the value and of queries'
    status = { { level, query }... }?                       a status dot: the first rule whose query is true
                                                            gives its level, none: "off". $value in a rule is
                                                            the view's value query
    dots = selector?, by = label?, states = { [value] = level }?   a dot per `by` (default "machine")
    when = query? }                                         shown only while true (non-zero)
  LEVELS                        "good", "warn", "bad", "off": green, yellow, red, gray
  FORMATS, COLORS               the allowed names, in the order the editor cycles them
  DEFAULT_STATES                states' default: running, ok, up, on, active, working good; idle, waiting off;
                                down, off, bad, broken bad. Any other state: warn
  format.view(view, v, total?, values?, status?) -> text, frac, level
    v: the value (nil: no data, text "–"); total: the `of` query's value; values: { [name] = number } for the
    text template; status: the status rules' level (for color = "status"). frac: 0..1 for a bar, or nil.
    level: "good" | "warn" | "bad" | "off" | nil ("sign": above 0 good, below 0 bad).
  format.expand(query, valueQuery) -> query   $value replaced by (valueQuery)
  format.dots(series, by?, states?) -> { { name, level }... }   series grouped by the `by` label (default
    "machine"), a dot per group, sorted by name. A series with a `state` label counts while its value is above 0,
    as states[state] (DEFAULT_STATES when not given; unknown: warn). A series without one: above 0 good, else
    bad. A group shows its most severe: bad, then warn, then good, then off.
  format.template(view, values) -> text
  format.number(v) -> "1.2M", "640", "0.25"
  format.duration(seconds) -> "45s", "12m", "2h 05m", "3d 4h"
]]

local format = {}

format.FORMATS = { "auto", "percent", "duration", "signed" }
format.COLORS = { "thresholds", "sign", "status", "none" }
format.LEVELS = { "good", "warn", "bad", "off" }
format.DEFAULT_STATES = { running = "good", ok = "good", up = "good", on = "good", active = "good", working = "good",
  idle = "off", waiting = "off", down = "bad", off = "bad", bad = "bad", broken = "bad" }

function format.number(v)
  if v == nil then return "–" end
  local a = math.abs(v)
  for _, u in ipairs({ { 1e18, "E" }, { 1e15, "P" }, { 1e12, "T" }, { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" } }) do
    if a >= u[1] then return (("%.1f"):format(v / u[1]):gsub("%.0$", "")) .. u[2] end
  end
  if v == math.floor(v) then return tostring(math.floor(v)) end
  return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

function format.duration(s)
  if s == nil then return "–" end
  local neg = s < 0 and "-" or ""
  s = math.floor(math.abs(s) + 0.5)
  if s < 60 then return neg .. s .. "s" end
  if s < 3600 then return neg .. (s // 60) .. "m" end
  if s < 86400 then return neg .. ("%dh %02dm"):format(s // 3600, (s % 3600) // 60) end
  return neg .. ("%dd %dh"):format(s // 86400, (s % 86400) // 3600)
end

local function level(view, v)
  if v == nil then return nil end
  local color = view.color or "thresholds"
  if color == "none" then return nil end
  if color == "sign" then
    if v > 0 then return "good" elseif v < 0 then return "bad" end
    return nil
  end
  if (view.badAbove and v >= view.badAbove) or (view.badBelow and v <= view.badBelow) then return "bad" end
  if (view.warnAbove and v >= view.warnAbove) or (view.warnBelow and v <= view.warnBelow) then return "warn" end
  return nil
end

-- One number as the view's format would show it, without a unit.
local function one(view, v)
  local kind = view.format or "auto"
  if v == nil then return "–" end
  if kind == "percent" then return math.floor(v * 100 + 0.5) .. "%" end
  if kind == "duration" then return format.duration(v) end
  if kind == "signed" then return (v > 0 and "+" or "") .. format.number(v) end
  return format.number(v)
end

function format.template(view, values)
  return (view.text:gsub("{([%w_]+)}", function(name)
    if values[name] == nil and not (name == "value" or name == "of" or (view.values or {})[name]) then return "?" end
    return one(view, values[name])
  end))
end

function format.expand(q, valueQuery)
  if not valueQuery then return q end
  return (q:gsub("%$value", function() return "(" .. valueQuery .. ")" end))
end

local SEVERITY = { bad = 4, warn = 3, good = 2, off = 1 }

function format.dots(series, by, states)
  by = by or "machine"
  states = states or format.DEFAULT_STATES
  local groups, names = {}, {}
  for _, s in ipairs(series or {}) do
    local labels = s.labels or {}
    local name = labels[by]
    if not name then
      local parts = {}
      for k, x in pairs(labels) do if k ~= "node" and k ~= "state" then parts[#parts + 1] = k .. "=" .. x end end
      table.sort(parts)
      name = #parts > 0 and table.concat(parts, " ") or (labels.node or "?")
    end
    local g = groups[name]
    if not g then g = { name = name }; groups[name] = g; names[#names + 1] = name end
    local on = s.value ~= nil and s.value > 0
    local lv
    if labels.state then
      if on then lv = states[labels.state] or "warn" end
    else
      lv = on and "good" or "bad"
    end
    if lv and (not g.level or SEVERITY[lv] > SEVERITY[g.level]) then g.level = lv end
  end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do out[#out + 1] = { name = name, level = groups[name].level } end
  return out
end

function format.view(view, v, total, values, status)
  local unit = view.unit and (" " .. view.unit) or ""
  local kind = view.format or "auto"
  local text, frac
  if view.of then
    text = format.number(v) .. "/" .. format.number(total) .. unit
    frac = (v and total and total > 0) and v / total or nil
  elseif kind == "percent" then
    text = v and (math.floor(v * 100 + 0.5) .. "%") or "–"
    frac = v
  else
    if kind == "duration" then
      text = format.duration(v)
    elseif kind == "signed" then
      text = v and ((v > 0 and "+" or "") .. format.number(v) .. unit) or "–"
    else
      text = format.number(v) .. (v and unit or "")
    end
    frac = (v and view.max) and v / view.max or nil
  end
  if view.text then
    local all = { value = v, of = total }
    for k, x in pairs(values or {}) do all[k] = x end
    text = format.template(view, all)
  end
  if frac then frac = math.max(0, math.min(1, frac)) end
  if view.color == "status" then return text, frac, status end
  return text, frac, level(view, v)
end

return format
