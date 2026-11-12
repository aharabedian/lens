--[[ lens.hub.viewdraft: a view being edited on the screen: its fields as text, the field being typed into,
  keys and pastes, and turning it back into a view. Pure.

  viewdraft.FIELDS               { { key, name, kind, choices? }... } in screen order. kind: "text", "number",
                                 "choice", or a table typed on one line: "values" (name=query; name=query),
                                 "states" (running=good; idle=off), "status" (bad: query; good: query)
  viewdraft.draft(view?) -> d    d.fields = { [key] = text }, d.focus = the field typed into ("label" first)
  viewdraft.key(d, char, code)   a key_down: printable characters type; Backspace deletes; Enter and Tab go to the
                                 next text field
  viewdraft.paste(d, text)       a clipboard event: appended to the focused field (line breaks become spaces)
  viewdraft.focus(d, key)        start typing into a field
  viewdraft.cycle(d, key)        a choice field: the next choice
  viewdraft.view(d) -> view | nil, err   numbers parsed, empty fields left out, checked like a panel
  viewdraft.KEYS                 the OpenComputers key codes it knows: back, enter, tab
]]

local config = require("lens.hub.config")
local format = require("lens.hub.format")
local textfield = require("lens.hub.textfield")

local viewdraft = {}

viewdraft.KEYS = textfield.KEYS

viewdraft.FIELDS = {
  { key = "label", name = "Label", kind = "text" },
  { key = "value", name = "Query", kind = "text" },
  { key = "format", name = "Format", kind = "choice", choices = format.FORMATS },
  { key = "unit", name = "Unit", kind = "text" },
  { key = "text", name = "Text", kind = "text" },
  { key = "values", name = "Values", kind = "values" },
  { key = "max", name = "Bar max", kind = "number" },
  { key = "of", name = "Bar of", kind = "text" },
  { key = "dots", name = "Dots", kind = "text" },
  { key = "by", name = "Dots by", kind = "text" },
  { key = "states", name = "Dot states", kind = "states" },
  { key = "status", name = "Status", kind = "status" },
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

local function parseValues(s, what)
  local out = {}
  for part in (s .. ";"):gmatch("(.-);") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      local name, q = part:match("^([%w_]+)%s*=%s*(.+)$")
      if not name then return nil, ("%s: write name=value; name=value (got %q)"):format(what or "Values", part) end
      out[name] = q
    end
  end
  return next(out) and out or nil
end

-- status rules as one line: "bad: query; warn: $value > 5", in order, and back.
local function statusText(rules)
  local parts = {}
  for _, r in ipairs(rules) do parts[#parts + 1] = r[1] .. ": " .. r[2] end
  return table.concat(parts, "; ")
end

local function parseStatus(s)
  local out = {}
  for part in (s .. ";"):gmatch("(.-);") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      local lv, q = part:match("^(%a+)%s*:%s*(.+)$")
      if not lv then return nil, ("Status: write level: query; level: query (got %q)"):format(part) end
      out[#out + 1] = { lv, q }
    end
  end
  return #out > 0 and out or nil
end

local function text(v, kind)
  if v == nil then return "" end
  if kind == "status" then return statusText(v) end
  if type(v) == "table" then return valuesText(v) end
  if math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then return tostring(math.floor(v)) end
  return tostring(v)
end

function viewdraft.draft(view)
  view = view or {}
  local d = { fields = {}, focus = "label" }
  for _, f in ipairs(viewdraft.FIELDS) do
    if f.kind == "choice" then
      d.fields[f.key] = view[f.key] or f.choices[1]
    else
      d.fields[f.key] = text(view[f.key], f.kind)
    end
  end
  return d
end

function viewdraft.focus(d, key)
  if BY[key] and BY[key].kind ~= "choice" then d.focus = key end
end

local function nextField(d)
  local seen = false
  for _, f in ipairs(viewdraft.FIELDS) do
    if seen and f.kind ~= "choice" then d.focus = f.key; return end
    if f.key == d.focus then seen = true end
  end
  d.focus = viewdraft.FIELDS[1].key
end

function viewdraft.key(d, char, code)
  local k = d.focus
  if not k then return end
  local typed, action = textfield.key(d.fields[k], char, code)
  d.fields[k] = typed
  if action then nextField(d) end
end

function viewdraft.paste(d, s)
  if d.focus then d.fields[d.focus] = textfield.paste(d.fields[d.focus], s) end
end

function viewdraft.cycle(d, key)
  local f = BY[key]
  if not f or f.kind ~= "choice" then return end
  for i, c in ipairs(f.choices) do
    if c == d.fields[key] then d.fields[key] = f.choices[i % #f.choices + 1]; return end
  end
  d.fields[key] = f.choices[1]
end

function viewdraft.view(d)
  local v = {}
  for _, f in ipairs(viewdraft.FIELDS) do
    local s = d.fields[f.key]
    if f.kind == "choice" then
      if s ~= f.choices[1] then v[f.key] = s end      -- the first choice is the default: left out
    else
      s = s:match("^%s*(.-)%s*$")
      if s ~= "" then
        if f.kind == "number" then
          local n = tonumber(s)
          if not n then return nil, f.name .. " must be a number" end
          v[f.key] = n
        elseif f.kind == "values" or f.kind == "states" then
          local t, err = parseValues(s, f.name)
          if err then return nil, err end
          v[f.key] = t
        elseif f.kind == "status" then
          local t, err = parseStatus(s)
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
