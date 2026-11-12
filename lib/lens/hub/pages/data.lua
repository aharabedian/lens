--[[ lens.hub.pages.data: the DATA page (lens.hub.editors.data): every metric, one metric's series, a query built
  by tapping.

  data.draw(f, e, actions)   e: { player, metrics = store:metrics, page, metric = one of them | nil,
                             labels = explore.labels, fn, funcs, query, value = text, series = { { labels, text,
                             rate? }... }, canPanel, canHud, editors = { name... } | nil, error, closesIn }

  At 100 columns or more the list and the metric sit side by side; narrower, they take turns (◀ METRICS).
]]

local Gui = require("lens.gui")
local frame = require("lens.hub.frame")

local data = {}

local C = frame.C

local function metricList(f, e, actions, x, y, width, last)
  f:heading(x, y, ("METRICS (%d)"):format(#e.metrics), width)
  y = y + 1
  if #e.metrics == 0 then
    f:text(x, y, Gui.fit("Nothing yet: waiting for agents to report.", width), C.dim)
    return
  end
  local per = math.max(1, last - y)                  -- leave a row for paging
  local pages = math.max(1, (#e.metrics + per - 1) // per)
  local page = math.min(e.page or 1, pages)
  for i = (page - 1) * per + 1, math.min(#e.metrics, page * per) do
    local mt = e.metrics[i]
    local chosen = e.metric and e.metric.name == mt.name
    local name, kind = mt.name, mt.type
    f:text(x, y, Gui.fit(mt.name, width - 10), chosen and C.text or C.dim, chosen and C.sel or nil)
    f:text(x + width - 9, y, Gui.rfit(tostring(mt.series), 3), C.dim)
    f:text(x + width - 5, y, mt.type == "counter" and "ctr" or "", C.dim)
    f:hit(x, y, x + width - 1, y, function(p) actions.dataPick(p, name, kind) end)
    y = y + 1
  end
  if pages > 1 then
    if page > 1 then f:button(x, last, "◀", function(p) actions.dataPage(p, -1) end) end
    f:text(x + 5, last, ("page %d of %d"):format(page, pages), C.dim)
    if page < pages then f:button(x + 19, last, "▶", function(p) actions.dataPage(p, 1) end) end
  end
end

-- Label values and functions to tap; returns the row after them.
local function builder(f, e, actions, x, y, width)
  for _, l in ipairs(e.labels) do
    local label = l.label
    f:text(x, y, Gui.fit(label, 9), C.dim)
    local items = { { "any", function(p) actions.dataFilter(p, label, nil) end, l.chosen == nil and C.btnOn or C.btn } }
    for _, v in ipairs(l.values) do
      local value = v
      items[#items + 1] = { Gui.fit(v, math.min(Gui.len(v), 20)), function(p) actions.dataFilter(p, label, value) end,
        l.chosen == v and C.btnOn or C.btn }
    end
    y = f:chips(x + 10, y, width - 10, items)
  end
  f:text(x, y, "combine", C.dim)
  local fns = {}
  for _, fn in ipairs(e.funcs) do
    local name = fn
    fns[#fns + 1] = { fn, function(p) actions.dataFn(p, name) end, e.fn == fn and C.btnOn or C.btn }
  end
  return f:chips(x + 10, y, width - 10, fns)
end

local function metricDetail(f, e, actions, x, y, width, last, narrow)
  local mt = e.metric
  if narrow then
    f:button(x, y, "◀ METRICS", actions.dataBack, C.line)
    y = y + 2
  end
  local title = mt.name .. (mt.unit and ("  (" .. mt.unit .. ")") or "") .. (mt.type == "counter" and "  counter" or "")
  f:text(x, y, Gui.fit(title, width), C.accent)
  y = y + 1
  if mt.help then f:text(x, y, Gui.fit(mt.help, width), C.dim); y = y + 1 end
  y = builder(f, e, actions, x, y + 1, width) + 1
  f:text(x, y, "query", C.dim)
  f:text(x + 10, y, Gui.fit(e.query, width - 10), C.text)
  f:text(x, y + 1, "value", C.dim)
  f:text(x + 10, y + 1, Gui.fit(e.value, width - 10), C.accent)
  y = y + 3
  local bx = x
  if e.canPanel then bx = f:button(bx, y, "SAVE AS PANEL", actions.dataPanel) end
  if e.canHud then bx = f:button(bx, y, "ADD TO MY HUD", actions.dataHud) end
  if not e.canPanel then
    f:text(bx, y, Gui.fit(("Only %s can add panels."):format(table.concat(e.editors or {}, ", ")), x + width - bx), C.dim)
  end
  y = y + 2
  f:heading(x, y, ("SERIES (%d)"):format(#e.series), width)
  y = y + 1
  for i, r in ipairs(e.series) do
    if y > last then break end
    if y == last and i < #e.series then
      f:text(x, y, ("+%d more"):format(#e.series - i + 1), C.dim)
      break
    end
    local value = r.text .. (r.rate and ("  " .. r.rate) or "")
    f:text(x, y, Gui.fit(r.labels, width - Gui.len(value) - 1), C.dim)
    f:text(x + width - Gui.len(value), y, value, C.text)
    y = y + 1
  end
end

function data.draw(f, e, actions)
  f:editorHeader("Data", { { "DONE", actions.dataDone } })
  local last = f.h - 2
  if f.w >= 100 then
    local lw = 44
    metricList(f, e, actions, 2, 3, lw, last)
    if e.metric then
      metricDetail(f, e, actions, 2 + lw + 3, 3, f.w - lw - 6, last, false)
    else
      f:text(2 + lw + 3, 4, "Tap a metric to see its series and build a query.", C.dim)
    end
  elseif e.metric then
    metricDetail(f, e, actions, 2, 3, f.w - 2, last, true)
  else
    metricList(f, e, actions, 2, 3, f.w - 2, last)
  end
  f:editorFooter(e)
end

return data
