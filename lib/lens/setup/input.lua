--[[ lens.setup.input: asking questions on the terminal (like prism-setup's).

  CANCEL                       raised (as an error value) when input ends (Ctrl+D)
  ask(prompt, default)         a line; blank -> default
  yes(prompt, default)         y/n -> boolean
  choose(labels, default)      numbered menu -> index
  number(prompt, default, min, max)   a whole number in range, asked again until it is one
  begin(steps), header(text)   numbered step headings ("2/4 Agents and panels")
]]

local I = {}

I.CANCEL = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function I.ask(prompt, default)
  io.write(prompt .. (default ~= nil and (" [" .. tostring(default) .. "]") or "") .. ": ")
  local line = io.read()
  if line == nil then error(I.CANCEL, 0) end
  line = trim(line)
  if line == "" then return default end
  return line
end

function I.yes(prompt, default)
  local a = I.ask(prompt .. " (y/n)", default and "y" or "n")
  return tostring(a):lower():sub(1, 1) == "y"
end

function I.choose(labels, default)
  for i, l in ipairs(labels) do print(("  %d) %s"):format(i, l)) end
  while true do
    local n = tonumber(I.ask(("  choose 1-%d"):format(#labels), default))
    if n and labels[n] then return n end
    print("  enter a number from the list")
  end
end

function I.number(prompt, default, min, max)
  while true do
    local n = tonumber(I.ask(prompt, default))
    if n and n == math.floor(n) and n >= min and n <= max then return math.floor(n) end
    print(("  enter a whole number from %d to %d"):format(min, max))
  end
end

local step, steps = 0, 0
function I.begin(n) step, steps = 0, n end
function I.header(text) step = step + 1; print(""); print(("%d/%d %s"):format(step, steps, text)) end

return I
