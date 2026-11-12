-- test_layout.lua: packaging contracts: manifest.lua lists every program and module, and puts them where
-- the programs look for them.
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
end
check(placed, "programs install to /home/bin and modules to /home/lib")

H.done()
