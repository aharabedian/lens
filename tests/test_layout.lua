-- test_layout.lua: packaging and structure contracts: manifest.lua lists every program and module and puts
-- them where the programs look for them; one version; no utf8 in src/ and lib/ (OpenOS has unicode); every
-- module names itself in its header; dependencies point one way (docs/architecture.md).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local check = H.check

local function lines(cmd) local out, p = {}, io.popen(cmd); for l in p:lines() do out[#out + 1] = l end; p:close(); return out end

local listed = {}
for _, f in ipairs(dofile(H.ROOT .. "/manifest.lua")) do listed[f[1]] = f[2] end

local missing = {}
for _, f in ipairs(lines('cd "' .. H.ROOT .. '" && find src lib -name "*.lua" 2>/dev/null | sort')) do
  if not listed[f] then missing[#missing + 1] = f end
end
check(#missing == 0, "manifest.lua lists every file in src/ and lib/"
  .. (#missing > 0 and (": missing " .. table.concat(missing, ", ")) or ""))

local absent = {}
for src in pairs(listed) do if not H.exists(H.ROOT .. "/" .. src) then absent[#absent + 1] = src end end
check(#absent == 0, "every file manifest.lua lists exists" .. (#absent > 0 and (": " .. table.concat(absent, ", ")) or ""))

local placed = true
for src, dest in pairs(listed) do
  if src:find("^src/") and dest ~= "bin/" .. src:sub(5) then placed = false end
  if src:find("^lib/") and dest ~= src then placed = false end
  if src:find("^config/") and dest ~= src:sub(8) then placed = false end
end
check(placed, "programs install to /home/bin and modules to /home/lib")

local utf = {}
for _, f in ipairs(lines('cd "' .. H.ROOT .. '" && grep -rl "utf8%.\\|utf8\\." src lib 2>/dev/null')) do utf[#utf + 1] = f end
check(#utf == 0, "src/ and lib/ use OpenOS unicode, not utf8" .. (#utf > 0 and (": " .. table.concat(utf, ", ")) or ""))

local function read(path) local f = io.open(H.ROOT .. "/" .. path); if not f then return nil end; local t = f:read("*a"); f:close(); return t end
local version = dofile(H.ROOT .. "/lib/lens/version.lua")
check(read("src/lens-update.lua"):match('local VERSION = "([^"]*)"') == version,
  "lens-update.lua's own VERSION matches lib/lens/version.lua")

-- Every module says what it is: its header comment starts with its own name (version.lua is just the string).
local unnamed = {}
for _, f in ipairs(lines('cd "' .. H.ROOT .. '" && find lib -name "*.lua" | sort')) do
  local name = f:gsub("^lib/", ""):gsub("%.lua$", ""):gsub("/", ".")
  local text = read(f) or ""
  if name ~= "lens.version" and not (text:find("^%-%-%[%[ " .. name:gsub("%.", "%%.") .. "[: ]")) then unnamed[#unnamed + 1] = f end
end
check(#unnamed == 0, "every module's header comment starts with its name" .. (#unnamed > 0 and (": " .. table.concat(unnamed, ", ")) or ""))

-- Dependencies point one way (docs/architecture.md). Each rule: modules matching `from` must not require
-- modules matching any of `deny`.
local RULES = {
  { from = "^lens%.metrics$", deny = { "^lens%." }, why = "agents vendor it: it needs nothing of LENS" },
  { from = "^lens%.codec$", deny = { "^lens%." }, why = "agents vendor it: it needs nothing of LENS" },
  { from = "^lens%.[%a]+$", deny = { "^lens%.hub", "^lens%.setup" }, why = "shared modules don't know the programs" },
  { from = "^lens%.hub%.pages%.", deny = { "^lens%.hub%.[^f]", "^lens%.setup" }, except = { "^lens%.hub%.frame$" },
    why = "pages only draw: lens.gui and lens.hub.frame" },
  { from = "^lens%.hub%.frame$", deny = { "^lens%.hub", "^lens%.setup" }, why = "frame only draws" },
  { from = "^lens%.hub%.editors%.", deny = { "^lens%.hub%.pages", "^lens%.hub%.dashboard", "^lens%.hub%.app",
    "^lens%.hub%.frame", "^lens%.gui" }, why = "editors hold state and actions; pages draw them" },
  { from = "^lens%.hub%.", deny = { "^lens%.hub%.app$", "^lens%.setup" }, why = "only the program uses the app" },
  { from = "^lens%.setup%.", deny = { "^lens%.hub%.[^c]", "^lens%.hub%.core" }, except = { "^lens%.hub%.config$" },
    why = "setup reads the hub's config checks, nothing else of it" },
}
local broken = {}
for _, f in ipairs(lines('cd "' .. H.ROOT .. '" && find lib -name "*.lua" | sort')) do
  local name = f:gsub("^lib/", ""):gsub("%.lua$", ""):gsub("/", ".")
  for dep in (read(f) or ""):gmatch('require%("([^"]+)"%)') do
    for _, r in ipairs(RULES) do
      if name:find(r.from) and dep ~= name then
        local allowed = false
        for _, e in ipairs(r.except or {}) do if dep:find(e) then allowed = true end end
        for _, d in ipairs(r.deny) do
          if not allowed and dep:find(d) then broken[#broken + 1] = ("%s -> %s (%s)"):format(name, dep, r.why) end
        end
      end
    end
  end
end
check(#broken == 0, "dependencies point one way" .. (#broken > 0 and (":\n    " .. table.concat(broken, "\n    ")) or ""))

-- Every Lua example in the docs loads: views (panels), rules, and whole hud = / panels = settings.
do
  local config = require("lens.hub.config")
  local bad = {}
  for _, doc in ipairs({ "docs/views.md", "docs/examples.md", "docs/hud.md", "docs/hub.md" }) do
    local text = read(doc) or ""
    local n = 0
    for block in text:gmatch("```lua\n(.-)```") do
      n = n + 1
      local body = block:gsub("^%s+", "")
      local wrapped
      if body:find("^hud%s*=") or body:find("^panels%s*=") then wrapped = "return { " .. body .. " }"
      elseif body:find("^{%s*id%s*=") then wrapped = "return { rules = { " .. body .. " } }"
      elseif body:find("^{%s*label%s*=") then wrapped = "return { panels = { " .. body .. " } }" end
      if wrapped then
        local chunk, err = load(wrapped, "=" .. doc, "t", {})
        local ok, c = false, err
        if chunk then ok, c = pcall(chunk) end
        local checked, why = nil, c
        if ok then checked, why = config.check(c) end
        if not checked then bad[#bad + 1] = ("%s example %d: %s"):format(doc, n, tostring(why)) end
      end
    end
  end
  check(#bad == 0, "every Lua example in the docs loads" .. (#bad > 0 and (":\n    " .. table.concat(bad, "\n    ")) or ""))
end

H.done()
