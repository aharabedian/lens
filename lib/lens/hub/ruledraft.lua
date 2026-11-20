--[[ lens.hub.ruledraft: an alert rule being made or changed on the screen (the rule editor): its fields as text,
  the field being typed into and the cursor, and turning it back into a rule (lens.hub.rules' form). Pure.

  ruledraft.FIELDS     { { key, name }... } in screen order: text, when (a query), for (seconds)
  ruledraft.draft(rule?) -> d   d.fields = { text, when, for }, d.level = "warn" | "bad", d.id (kept when changing
                                one), d.focus = a field key, d.cursor
  ruledraft.focus(d, key, cursor?)   start typing there (cursor: at the end when not given)
  ruledraft.key(d, char, code)       a key_down (lens.hub.textfield); Enter, Tab and ↓ go to the next field, ↑ back
  ruledraft.paste(d, text)
  ruledraft.level(d)                 warn <-> bad
  ruledraft.rule(d) -> rule | nil, err   checked like a rule in lens-hub.cfg; a new one's id comes from its text
  ruledraft.slug(text) -> id         "Low power while the ore line works" -> "low-power-while-the-ore-line-works"
]]

local rules = require("lens.hub.rules")
local textfield = require("lens.hub.textfield")

local ruledraft = {}

ruledraft.FIELDS = {
  { key = "text", name = "Text" },
  { key = "when", name = "When" },
  { key = "for", name = "For (s)" },
}

function ruledraft.draft(r)
  r = r or {}
  return { fields = { text = r.text or "", when = r.when or "", ["for"] = r["for"] and tostring(r["for"]) or "0" },
    level = r.level == "bad" and "bad" or "warn", id = r.id, focus = "text", cursor = nil }
end

function ruledraft.focus(d, key, cursor)
  d.focus, d.cursor = key, cursor
end

local function step(d, dir)
  for i, f in ipairs(ruledraft.FIELDS) do
    if f.key == d.focus then
      local n = ruledraft.FIELDS[i + dir]
      if n then d.focus, d.cursor = n.key, nil end
      return
    end
  end
end

function ruledraft.key(d, char, code)
  if not d.focus then return end
  local text, cursor, action = textfield.key(d.fields[d.focus], d.cursor, char, code)
  d.fields[d.focus], d.cursor = text, cursor
  if action == "enter" or action == "tab" or action == "down" then step(d, 1)
  elseif action == "up" then step(d, -1) end
end

function ruledraft.paste(d, s)
  if not d.focus then return end
  d.fields[d.focus], d.cursor = textfield.paste(d.fields[d.focus], d.cursor, s)
end

function ruledraft.level(d) d.level = d.level == "bad" and "warn" or "bad" end

function ruledraft.slug(text)
  local s = tostring(text):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return s:sub(1, 40)
end

function ruledraft.rule(d)
  local text = d.fields.text:match("^%s*(.-)%s*$")
  if text == "" then return nil, "an alert needs a text" end
  local when = d.fields.when:match("^%s*(.-)%s*$")
  if when == "" then return nil, "an alert needs a query in When" end
  local hold = tonumber(d.fields["for"]:match("^%s*(.-)%s*$") ~= "" and d.fields["for"] or "0")
  if not hold or hold < 0 then return nil, "For is seconds: 0 or more" end
  local id = d.id or ruledraft.slug(text)
  if id == "" then id = "alert" end
  local r = { id = id, text = text, when = when, level = d.level, ["for"] = hold }
  local _, err = rules.new({ r })
  if err then return nil, (err:gsub("^rule [^:]*: ", "")) end
  return r
end

return ruledraft
