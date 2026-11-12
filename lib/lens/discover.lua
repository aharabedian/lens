--[[ lens.discover: describe the components attached to a computer, with every method and its doc string.
  For designing against a mod's real API (glasses, GT energy, IC2 reactors) instead of guessing.

  discover.report(component, opts) -> lines[], summary[]
    component: OpenOS `component` (list, methods, doc)
    opts.filter: only types containing this text; opts.all: include the basics (gpu, screen, filesystem...)
    lines: the full report (every component, methods sorted, with docs); summary: one line per component
]]

local discover = {}

-- Parts of every computer: listed in the summary, but their methods only with `all` or a filter naming them.
discover.BASICS = {
  computer = true, eeprom = true, filesystem = true, gpu = true, internet = true, keyboard = true,
  modem = true, screen = true,
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

return discover
