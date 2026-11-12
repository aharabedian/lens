--[[ lens.hub.format: a view's value as text, a bar fraction and a color level, the same on the dashboard and
  in the HUD. Pure.

  A view (a panel, a HUD bar or text): { label, value = query, of = query?, max?, unit?,
    format = "auto" | "percent" | "duration" | "signed",   default "auto" ("percent": value is 0..1)
    color = "thresholds" | "sign" | "none",                 default "thresholds"
    warnAbove?, badAbove?, warnBelow?, badBelow? }          (thresholds compare the value itself)
  FORMATS, COLORS               the allowed names, in the order the editor cycles them
  format.view(view, v, total?) -> text, frac, level
    v: the value (nil: no data, text "–"); total: the `of` query's value. frac: 0..1 for a bar, or nil.
    level: "bad" | "warn" | "good" | nil. "sign": above 0 good, below 0 bad.
  format.number(v) -> "1.2M", "640", "0.25"
  format.duration(seconds) -> "45s", "12m", "2h 05m", "3d 4h"
]]

local format = {}

format.FORMATS = { "auto", "percent", "duration", "signed" }
format.COLORS = { "thresholds", "sign", "none" }

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

function format.view(view, v, total)
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
  if frac then frac = math.max(0, math.min(1, frac)) end
  return text, frac, level(view, v)
end

return format
