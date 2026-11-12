--[[ lens.hub.viewdraft: a view being edited on the screen: its fields as text, its status rules and dot states
  as rows, the field being typed into and where the cursor is, and turning it back into a view. Pure.

  viewdraft.FIELDS     { { key, name, kind, choices? }... } in screen order. kind: "text", "number", "choice",
                       "values" (typed on one line: name=query; name=query), "status" (rule rows), "states"
                       (state rows)
  viewdraft.LEVELS     the colors a rule or state cycles through: good, warn, bad, off
  viewdraft.draft(view?) -> d
    d.fields = { [key] = text } for the one-line fields; d.choices = { [key] = choice };
    d.rules = { { level, query }... } (status, in order); d.states = { { name, level }... } (dot states);
    d.focus = what's being typed into: a field key, "rule:<i>" (rule i's query) or "state:<i>" (state i's
    name); d.cursor = characters before the cursor
  viewdraft.text(d, focus) -> text           what's in a field or row
  viewdraft.focus(d, focus, cursor?)         start typing there (cursor: at the end when not given)
  viewdraft.key(d, char, code)               a key_down, through lens.hub.textfield: typing, ← → Home End,
                                             Backspace, Delete; Enter, Tab and ↓ go to the next field, ↑ back
  viewdraft.paste(d, text)                   a clipboard event, at the cursor
  viewdraft.cycle(d, key)                    a choice field: the next choice
  viewdraft.ruleLevel(d, i), viewdraft.stateLevel(d, i)   a row's color: the next of LEVELS
  viewdraft.addRule(d), viewdraft.removeRule(d, i), viewdraft.moveRule(d, i, -1 | 1)
  viewdraft.addState(d), viewdraft.removeState(d, i)       (adding focuses the new row)
  viewdraft.view(d) -> view | nil, err       numbers parsed, empty fields and rows left out, checked like a panel
  viewdraft.KEYS                             lens.hub.textfield's key codes
]]

local unicode = require("unicode")
local config = require("lens.hub.config")
local format = require("lens.hub.format")
local textfield = require("lens.hub.textfield")

local viewdraft = {}

viewdraft.KEYS = textfield.KEYS
viewdraft.LEVELS = format.LEVELS

viewdraft.FIELDS = {
  { key = "label", name = "Label", kind = "text" },
  { key = "value", name = "Query", kind = "text" },
  { key = "format", name = "Format", kind = "choice", choices = format.FORMATS },
  { key = "unit", name = "Unit", kind = "text" },
  { key = "text", name = "Text", kind = "text" },
  { key = "values", name = "Values", kind = "values" },
  { key = "max", name = "Bar max", kind = "number" },
  { key = "of", name = "Bar of", kind = "text" },
  { key = "status", name = "Status", kind = "status" },
  { key = "dots", name = "Dots", kind = "text" },
  { key = "by", name = "Dots by", kind = "text" },
  { key = "states", name = "Dot states", kind = "states" },
  { key = "color", name = "Color", kind = "choice", choices = format.COLORS },
  { key = "warnAbove", name = "Warn above", kind = "number" },
  { key = "badAbove", name = "Bad above", kind = "number" },
  { key = "warnBelow", name = "Warn below", kind = "number" },
  { key = "badBelow", name = "Bad below", kind = "number" },
  { key = "when", name = "Show when", kind = "text" },
}

local BY = {}
for _, f in ipairs(viewdraft.FIELDS) do BY[f.key] = f end

-- values as one line: "a=query; b=query" (names sorted), and back.
local function valuesText(t)
  local names = {}
  for k in pairs(t) do names[#names + 1] = k end
  table.sort(names)
  local parts = {}
  for _, k in ipairs(names) do parts[#parts + 1] = k .. "=" .. t[k] end
  return table.concat(parts, "; ")
end

local function parseValues(s)
  local out = {}
  for part in (s .. ";"):gmatch("(.-);") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      local name, q = part:match("^([%w_]+)%s*=%s*(.+)$")
      if not name then return nil, ("Values: write name=query; name=query (got %q)"):format(part) end
      out[name] = q
    end
  end
  return next(out) and out or nil
end

local function asText(v)
  if v == nil then return "" end
  if type(v) == "table" then return valuesText(v) end
  if math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then return tostring(math.floor(v)) end
  return tostring(v)
end

function viewdraft.draft(view)
  view = view or {}
  local d = { fields = {}, choices = {}, rules = {}, states = {}, focus = "label" }
  for _, f in ipairs(viewdraft.FIELDS) do
    if f.kind == "choice" then
      d.choices[f.key] = view[f.key] or f.choices[1]
    elseif f.kind ~= "status" and f.kind ~= "states" then
      d.fields[f.key] = asText(view[f.key])
    end
  end
  for _, r in ipairs(view.status or {}) do d.rules[#d.rules + 1] = { r[1], r[2] } end
  local names = {}
  for name in pairs(view.states or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do d.states[#d.states + 1] = { name, view.states[name] } end
  d.cursor = unicode.len(d.fields.label)
  return d
end

-- What's typed into a focus, and putting it back.
local function slot(focus)
  local kind, i = focus:match("^(%a+):(%d+)$")
  return kind, tonumber(i)
end

function viewdraft.text(d, focus)
  local kind, i = slot(focus)
  if kind == "rule" then return d.rules[i] and d.rules[i][2] or "" end
  if kind == "state" then return d.states[i] and d.states[i][1] or "" end
  return d.fields[focus] or ""
end

local function set(d, focus, text)
  local kind, i = slot(focus)
  if kind == "rule" then if d.rules[i] then d.rules[i][2] = text end
  elseif kind == "state" then if d.states[i] then d.states[i][1] = text end
  else d.fields[focus] = text end
end

function viewdraft.focus(d, focus, cursor)
  local kind, i = slot(focus)
  local ok = (kind == "rule" and d.rules[i]) or (kind == "state" and d.states[i])
    or (BY[focus] and d.fields[focus] ~= nil)
  if not ok then return end
  d.focus = focus
  local n = unicode.len(viewdraft.text(d, focus))
  d.cursor = math.max(0, math.min(cursor or n, n))
end

-- Every place to type, in screen order.
local function stops(d)
  local out = {}
  for _, f in ipairs(viewdraft.FIELDS) do
    if f.kind == "status" then
      for i = 1, #d.rules do out[#out + 1] = "rule:" .. i end
    elseif f.kind == "states" then
      for i = 1, #d.states do out[#out + 1] = "state:" .. i end
    elseif f.kind ~= "choice" then
      out[#out + 1] = f.key
    end
  end
  return out
end

local function step(d, dir)
  local list = stops(d)
  for i, s in ipairs(list) do
    if s == d.focus then
      viewdraft.focus(d, list[(i - 1 + dir) % #list + 1])
      return
    end
  end
  viewdraft.focus(d, list[1])
end

function viewdraft.key(d, char, code)
  if not d.focus then return end
  local text, cursor, action = textfield.key(viewdraft.text(d, d.focus), d.cursor, char, code)
  set(d, d.focus, text)
  d.cursor = cursor
  if action == "enter" or action == "tab" or action == "down" then step(d, 1)
  elseif action == "up" then step(d, -1) end
end

function viewdraft.paste(d, s)
  if not d.focus then return end
  local text, cursor = textfield.paste(viewdraft.text(d, d.focus), d.cursor, s)
  set(d, d.focus, text)
  d.cursor = cursor
end

local function nextOf(list, current)
  for i, c in ipairs(list) do if c == current then return list[i % #list + 1] end end
  return list[1]
end

function viewdraft.cycle(d, key)
  local f = BY[key]
  if f and f.kind == "choice" then d.choices[key] = nextOf(f.choices, d.choices[key]) end
end

function viewdraft.ruleLevel(d, i) if d.rules[i] then d.rules[i][1] = nextOf(viewdraft.LEVELS, d.rules[i][1]) end end
function viewdraft.stateLevel(d, i) if d.states[i] then d.states[i][2] = nextOf(viewdraft.LEVELS, d.states[i][2]) end end

function viewdraft.addRule(d)
  d.rules[#d.rules + 1] = { "good", "" }
  viewdraft.focus(d, "rule:" .. #d.rules)
end

function viewdraft.addState(d)
  d.states[#d.states + 1] = { "", "good" }
  viewdraft.focus(d, "state:" .. #d.states)
end

-- After a row goes, focus can't point at it (or at a row that moved).
local function refocus(d, kind)
  if d.focus and d.focus:find("^" .. kind .. ":") then viewdraft.focus(d, "label") end
end

function viewdraft.removeRule(d, i) table.remove(d.rules, i); refocus(d, "rule") end
function viewdraft.removeState(d, i) table.remove(d.states, i); refocus(d, "state") end

function viewdraft.moveRule(d, i, dir)
  local j = i + dir
  if d.rules[i] and d.rules[j] then
    d.rules[i], d.rules[j] = d.rules[j], d.rules[i]
    refocus(d, "rule")
  end
end

function viewdraft.view(d)
  local v = {}
  for _, f in ipairs(viewdraft.FIELDS) do
    if f.kind == "choice" then
      local c = d.choices[f.key]
      if c ~= f.choices[1] then v[f.key] = c end      -- the first choice is the default: left out
    elseif f.kind == "status" then
      local rules = {}
      for _, r in ipairs(d.rules) do
        local q = r[2]:match("^%s*(.-)%s*$")
        if q ~= "" then rules[#rules + 1] = { r[1], q } end
      end
      if #rules > 0 then v.status = rules end
    elseif f.kind == "states" then
      local states = {}
      for _, st in ipairs(d.states) do
        local name = st[1]:match("^%s*(.-)%s*$")
        if name ~= "" then states[name] = st[2] end
      end
      if next(states) then v.states = states end
    else
      local s = d.fields[f.key]:match("^%s*(.-)%s*$")
      if s ~= "" then
        if f.kind == "number" then
          local n = tonumber(s)
          if not n then return nil, f.name .. " must be a number" end
          v[f.key] = n
        elseif f.kind == "values" then
          local t, err = parseValues(s)
          if err then return nil, err end
          v[f.key] = t
        else
          v[f.key] = s
        end
      end
    end
  end
  if v.max and v.of then return nil, "use Bar max or Bar of, not both" end
  local err = config.checkView(v)
  if err then return nil, err end
  return v
end

return viewdraft
