--[[ lens.hub.viewdraft: a view being edited on the screen: its fields as text, the field being typed into,
  keys and pastes, and turning it back into a view. Pure.

  viewdraft.FIELDS               { { key, name, kind = "text" | "number" | "choice", choices? }... } in screen order
  viewdraft.draft(view?) -> d    d.fields = { [key] = text }, d.focus = the field typed into ("label" first)
  viewdraft.key(d, char, code)   a key_down: printable characters type; Backspace deletes; Enter and Tab go to the
                                 next text field
  viewdraft.paste(d, text)       a clipboard event: appended to the focused field (line breaks become spaces)
  viewdraft.focus(d, key)        start typing into a field
  viewdraft.cycle(d, key)        a choice field: the next choice
  viewdraft.view(d) -> view | nil, err   numbers parsed, empty fields left out, checked like a panel
  viewdraft.KEYS                 the OpenComputers key codes it knows: back, enter, tab
]]

local unicode = require("unicode")
local config = require("lens.hub.config")
local format = require("lens.hub.format")

local viewdraft = {}

viewdraft.KEYS = { back = 0x0E, enter = 0x1C, tab = 0x0F }

viewdraft.FIELDS = {
  { key = "label", name = "Label", kind = "text" },
  { key = "value", name = "Query", kind = "text" },
  { key = "format", name = "Format", kind = "choice", choices = format.FORMATS },
  { key = "unit", name = "Unit", kind = "text" },
  { key = "max", name = "Bar max", kind = "number" },
  { key = "of", name = "Bar of", kind = "text" },
  { key = "color", name = "Color", kind = "choice", choices = format.COLORS },
  { key = "warnAbove", name = "Warn above", kind = "number" },
  { key = "badAbove", name = "Bad above", kind = "number" },
  { key = "warnBelow", name = "Warn below", kind = "number" },
  { key = "badBelow", name = "Bad below", kind = "number" },
}

local BY = {}
for _, f in ipairs(viewdraft.FIELDS) do BY[f.key] = f end

local function text(v)
  if v == nil then return "" end
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
      d.fields[f.key] = text(view[f.key])
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
  if code == viewdraft.KEYS.enter or code == viewdraft.KEYS.tab then
    nextField(d)
  elseif code == viewdraft.KEYS.back then
    local s = d.fields[k]
    d.fields[k] = unicode.len(s) > 0 and unicode.sub(s, 1, -2) or ""
  elseif type(char) == "number" and char >= 32 and char ~= 127 then
    d.fields[k] = d.fields[k] .. unicode.char(math.floor(char))
  end
end

function viewdraft.paste(d, s)
  if d.focus and type(s) == "string" then d.fields[d.focus] = d.fields[d.focus] .. s:gsub("[\r\n\t]+", " ") end
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
