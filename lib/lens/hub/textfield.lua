--[[ lens.hub.textfield: one line of text being typed on the hub's keyboard. Pure.

  textfield.key(text, char, code, max?) -> text, action
    a key_down: printable characters are added (up to max characters), Backspace deletes the last one.
    action: "enter" for Enter, "tab" for Tab, else nil (the caller decides what they mean).
  textfield.paste(text, s, max?) -> text   a clipboard event: added, line breaks and tabs as spaces
  textfield.KEYS                           the OpenComputers key codes it knows: back, enter, tab
]]

local unicode = require("unicode")

local textfield = {}

textfield.KEYS = { back = 0x0E, enter = 0x1C, tab = 0x0F }

local function cap(s, max)
  if max and unicode.len(s) > max then return unicode.sub(s, 1, max) end
  return s
end

function textfield.key(text, char, code, max)
  local K = textfield.KEYS
  if code == K.enter then return text, "enter" end
  if code == K.tab then return text, "tab" end
  if code == K.back then return unicode.len(text) > 0 and unicode.sub(text, 1, -2) or "", nil end
  if type(char) == "number" and char >= 32 and char ~= 127 then return cap(text .. unicode.char(math.floor(char)), max), nil end
  return text, nil
end

function textfield.paste(text, s, max)
  if type(s) ~= "string" then return text end
  return cap(text .. s:gsub("[\r\n\t]+", " "), max)
end

return textfield
