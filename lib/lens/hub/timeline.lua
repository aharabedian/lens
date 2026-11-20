--[[ lens.hub.timeline: the LOG page's timeline: for each node, its worst alert in each slice of the last hours,
  and where it restarted. Pure.

  timeline.bands(entries, time, span, cols, max?) -> { rows = { row... }, more = n, step = seconds per column }
    entries: lens.hub.logbook entries (an "alert" has node, level, since and at; a "restart" has node and at),
             plus the alerts happening now (since, no at: on until `time`). Times are real seconds.
    time: now; span: seconds shown (the last 12 or 24 hours); cols: columns, oldest first, the last ending now.
    row = { node, cells = { [col] = "bad" | "warn" | nil }, marks = { [col] = true } (restarts) }
    Rows are the nodes with an alert or a restart in the span, by name; at most max (default 8): `more` says how
    many weren't shown.
  timeline.ticks(time, span, cols, tz?) -> { { col, text }... }   labels for the hours along the top: clock times
    ("22:00") with tz (hours from UTC), else how long ago ("-6h"); every 2 hours for 12, every 4 for 24, none
    closer than 7 columns to the next or to "now" at the end
]]

local timeline = {}

local RANK = { warn = 1, bad = 2 }

function timeline.bands(entries, time, span, cols, max)
  max = max or 8
  local start = time - span
  local step = span / cols
  local byNode, names = {}, {}
  local function rowFor(node)
    local r = byNode[node]
    if not r then
      r = { node = node, cells = {}, marks = {} }
      byNode[node] = r
      names[#names + 1] = node
    end
    return r
  end
  local function col(t) return math.max(1, math.min(cols, math.floor((t - start) / step) + 1)) end
  for _, e in ipairs(entries) do
    local node = e.node
    if node and e.kind ~= "restart" and RANK[e.level] and e.since then
      local stop = e.at or time
      if stop > start and e.since <= time then
        local r = rowFor(node)
        for c = col(math.max(e.since, start)), col(math.min(stop, time)) do
          local was = r.cells[c]
          if not was or RANK[e.level] > RANK[was] then r.cells[c] = e.level end
        end
      end
    elseif node and e.kind == "restart" and e.at and e.at > start and e.at <= time then
      rowFor(node).marks[col(e.at)] = true
    end
  end
  table.sort(names)
  local rows = {}
  for i = 1, math.min(max, #names) do rows[i] = byNode[names[i]] end
  return { rows = rows, more = math.max(0, #names - max), step = step }
end

function timeline.ticks(time, span, cols, tz)
  local every = span > 12 * 3600 and 4 * 3600 or 2 * 3600
  local start = time - span
  local step = span / cols
  local out, lastEnd = {}, 0
  local shift = tz and tz * 3600 or 0
  -- The first boundary after start: on the clock with tz, else counted back from now.
  local t
  if tz then
    t = (math.floor((start + shift) / every) + 1) * every - shift
  else
    t = time - math.floor(span / every) * every
    if t <= start then t = t + every end
  end
  while t < time do
    local c = math.floor((t - start) / step) + 1
    local text
    if tz then
      local s = math.floor(t + shift) % 86400
      text = ("%02d:%02d"):format(s // 3600, (s % 3600) // 60)
    else
      text = ("-%dh"):format(math.floor((time - t) / 3600 + 0.5))
    end
    if c > lastEnd + 1 and c + #text + 1 < cols - 2 then
      out[#out + 1] = { c, text }
      lastEnd = c + #text
    end
    t = t + every
  end
  out[#out + 1] = { cols - 2, "now" }
  return out
end

return timeline
