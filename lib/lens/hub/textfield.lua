--[[ lens.hub.textfield: one line of text being typed on the hub's keyboard, with a cursor. Pure.

  cursor: how many characters are before it (0 .. length); nil means at the end.
  textfield.key(text, cursor, char, code, max?) -> text, cursor, action
    a key_down. Printable characters are inserted at the cursor (up to max characters); Backspace deletes the
    one before it, Delete the one after; ← → move it, Home and End jump to the ends.
    action: "enter" for Enter, "tab" for Tab, "up" / "down" for ↑ ↓, else nil (the caller decides).
  textfield.paste(text, cursor, s, max?) -> text, cursor   a clipboard event: inserted at the cursor, line breaks
                                           and tabs as spaces
  textfield.KEYS                           the OpenComputers key codes it knows
]]

local unicode = require("unicode")

local textfield = {}

textfield.KEYS = { back = 0x0E, enter = 0x1C, tab = 0x0F, left = 0xCB, right = 0xCD, home = 0xC7, ["end"] = 0xCF,
  delete = 0xD3, up = 0xC8, down = 0xD0 }

local function clampCursor(text, cursor)
  local n = unicode.len(text)
  if cursor == nil or cursor > n then return n end
  return math.max(0, cursor)
end

local function insert(text, cursor, s, max)
  local before, after = unicode.sub(text, 1, cursor), unicode.sub(text, cursor + 1)
  if max then
    local room = max - unicode.len(text)
    if room <= 0 then return text, cursor end
    if unicode.len(s) > room then s = unicode.sub(s, 1, room) end
  end
  return before .. s .. after, cursor + unicode.len(s)
end

function textfield.key(text, cursor, char, code, max)
  local K = textfield.KEYS
  cursor = clampCursor(text, cursor)
  local n = unicode.len(text)
  if code == K.enter then return text, cursor, "enter" end
  if code == K.tab then return text, cursor, "tab" end
  if code == K.up then return text, cursor, "up" end
  if code == K.down then return text, cursor, "down" end
  if code == K.left then return text, math.max(0, cursor - 1), nil end
  if code == K.right then return text, math.min(n, cursor + 1), nil end
  if code == K.home then return text, 0, nil end
  if code == K["end"] then return text, n, nil end
  if code == K.back then
    if cursor == 0 then return text, 0, nil end
    return unicode.sub(text, 1, cursor - 1) .. unicode.sub(text, cursor + 1), cursor - 1, nil
  end
  if code == K.delete then
    if cursor >= n then return text, cursor, nil end
    return unicode.sub(text, 1, cursor) .. unicode.sub(text, cursor + 2), cursor, nil
  end
  if type(char) == "number" and char >= 32 and char ~= 127 then
    local t, c = insert(text, cursor, unicode.char(math.floor(char)), max)
    return t, c, nil
  end
  return text, cursor, nil
end

function textfield.paste(text, cursor, s, max)
  cursor = clampCursor(text, cursor)
  if type(s) ~= "string" then return text, cursor end
  return insert(text, cursor, (s:gsub("[\r\n\t]+", " ")), max)
end

return textfield
