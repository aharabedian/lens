--[[ lens.discover: describe the components attached to a computer, with every method and its doc string.
  For designing against a mod's real API (glasses, GT energy, IC2 reactors) instead of guessing.

  discover.report(component, opts) -> lines[], summary[]
    component: OpenOS `component` (list, methods, doc)
    opts.filter: only types containing this text; opts.all: include the basics (gpu, screen, filesystem...)
    lines: the full report (every component, methods sorted, with docs); summary: one line per component

  discover.widgets(proxy) -> lines[]
    For a component whose add*() methods return objects (OC Glasses' Glasses Terminal): creates one of each
    2D widget, lists what the object offers, and removes it again. An object that can't be listed (pairs
    gives nothing) is tried against GUESSES: the names found are reported as "(found by name)".
    Widgets are removed with removeObject(id) when the object tells its id, else with removeAll() when
    there were no widgets before; otherwise the report says how many it left.

  discover.event(ev) -> line   one pulled event as text, for --events

  discover.glassesTest(proxy) -> ids[], lines[]
    Draws a calibration pattern on a Glasses Terminal, for what the first one (2026-11-12) left open:
      a green bar setSize(10, 80): wide and short if setSize takes the height first, as it seemed
      "Scale 1", "Scale 0.5", "Scale 2", with setScale called before setText this time
    Returns the widget ids (to removeObject later) and what to look for.
]]

local discover = {}

-- Parts of every computer: listed in the summary, but their methods only with `all` or a filter naming them.
discover.BASICS = {
  computer = true, eeprom = true, filesystem = true, gpu = true, internet = true, keyboard = true,
  modem = true, screen = true,
}

discover.WIDGETS = { "addTextLabel", "addRect", "addQuad", "addDot", "addTriangle", "addItem" }

-- Method names widget libraries commonly use, tried when an object can't be listed.
discover.GUESSES = {
  "getID", "getId", "id", "remove", "setText", "getText", "setColor", "getColor", "setAlpha", "setPosition",
  "getPosition", "setSize", "getSize", "setScale", "setVisible", "isVisible", "setVertex", "setItem",
  "setFontSize", "setShadow", "setAlignment", "addColor", "addTranslation", "addScale", "addRotation",
  "addAutoTranslation", "removeModifier", "getModifiers", "setCondition", "setEasing", "setHorizontalAlign",
  "setVerticalAlign", "setCulling", "setLookingAt", "setViewDistance", "setFaceWidgetToPlayer", "setFont",
  "setAntialias", "setWidth", "setHeight", "updateModifier",
}

function discover.report(component, opts)
  opts = opts or {}
  local found = {}
  for addr, ctype in component.list() do found[#found + 1] = { addr = addr, type = ctype } end
  table.sort(found, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.addr < b.addr
  end)

  local lines, summary = {}, {}
  for _, c in ipairs(found) do
    local wanted = opts.filter and c.type:find(opts.filter, 1, true)
    local detailed = wanted or (not opts.filter and (opts.all or not discover.BASICS[c.type]))
    local methods = {}
    if detailed then
      for name in pairs(component.methods(c.addr) or {}) do methods[#methods + 1] = name end
      table.sort(methods)
    end
    summary[#summary + 1] = ("%-24s %s%s"):format(c.type, c.addr,
      detailed and (" (" .. #methods .. " methods)") or "")
    if detailed then
      lines[#lines + 1] = ("== %s %s"):format(c.type, c.addr)
      for _, name in ipairs(methods) do
        local ok, doc = pcall(component.doc, c.addr, name)
        lines[#lines + 1] = ("  %s  %s"):format(name, (ok and doc) or "")
      end
      lines[#lines + 1] = ""
    end
  end
  return lines, summary
end

local function describeValue(v)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t == "table" or t == "function" or t == "userdata" then return t end
  return tostring(v)
end

-- What an object offers: listed fields, or the guessed names it answers to.
local function inspect(obj)
  local out, listed = {}, false
  local ok = pcall(function()
    for k, v in pairs(obj) do
      listed = true
      out[#out + 1] = ("    %s  %s"):format(tostring(k), describeValue(v))
    end
  end)
  table.sort(out)
  if not ok or not listed then
    local mt = getmetatable(obj)
    if type(mt) == "table" then
      local keys = {}
      for k in pairs(mt) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      out[#out + 1] = "    (metatable: " .. table.concat(keys, ", ") .. ")"
    end
    for _, name in ipairs(discover.GUESSES) do
      local got, v = pcall(function() return obj[name] end)
      if got and v ~= nil then out[#out + 1] = ("    %s  %s (found by name)"):format(name, describeValue(v)) end
    end
  end
  return out
end

local function idOf(obj)
  for _, name in ipairs({ "getID", "getId" }) do
    local ok, id = pcall(function() return obj[name]() end)
    if ok and id ~= nil then return id end
  end
  local ok, id = pcall(function() return obj.id end)
  if ok and type(id) == "number" then return id end
end

function discover.widgets(proxy)
  local lines = {}
  local okCount, before = pcall(proxy.getObjectCount)
  before = okCount and before or nil
  local leftover = 0
  for _, add in ipairs(discover.WIDGETS) do
    if proxy[add] then
      local ok, obj = pcall(proxy[add])
      if not ok then
        lines[#lines + 1] = ("== %s() failed: %s"):format(add, tostring(obj))
      else
        lines[#lines + 1] = ("== %s() -> %s"):format(add, type(obj))
        for _, l in ipairs(inspect(obj)) do lines[#lines + 1] = l end
        local id = idOf(obj)
        if id ~= nil and proxy.removeObject then
          local removed = pcall(proxy.removeObject, id)
          lines[#lines + 1] = ("    id %s, removed: %s"):format(tostring(id), tostring(removed))
        else
          leftover = leftover + 1
        end
      end
      lines[#lines + 1] = ""
    end
  end
  if leftover > 0 then
    if before == 0 and proxy.removeAll then
      pcall(proxy.removeAll)
      lines[#lines + 1] = "removed the test widgets with removeAll() (there were none before)"
    else
      lines[#lines + 1] = ("left %d test widget(s): there were %s before, so removeAll() wasn't used")
        :format(leftover, tostring(before))
    end
  end
  return lines
end

function discover.glassesTest(proxy)
  local ids = {}
  local function keep(w) ids[#ids + 1] = w.getID(); return w end
  local bar = keep(proxy.addRect())
  bar.setPosition(10, 10); bar.setSize(10, 80); bar.setColor(0, 1, 0)
  local function text(y, s, scale)
    local o = keep(proxy.addTextLabel())
    if scale then o.setScale(scale) end
    o.setPosition(10, y); o.setColor(1, 1, 1); o.setText(s)
  end
  text(26, "Scale 1 - LENS test 2")
  text(44, "Scale 0.5", 0.5)
  text(56, "Scale 2", 2)
  return ids, {
    "Look through the glasses:",
    "  1. Is the green bar wide and short (80 x 10), or tall and thin?",
    "  2. Are 'Scale 0.5' and 'Scale 2' half and twice the size of 'Scale 1'?",
  }
end

function discover.event(ev)
  local parts = {}
  for i = 1, ev.n or #ev do parts[#parts + 1] = describeValue(ev[i]) end
  return table.concat(parts, "  ")
end

return discover
