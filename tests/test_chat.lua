-- test_chat.lua: alerts in chat through lens-hub with two Glasses Terminals: with chat = true each new BAD alert goes to
-- the chat of each wearer whose HUD would list it (sendMessageTo(player, text), arguments assumed: lens-discover --chat
-- checks), not WARNs, at most 5 a minute each; chat off by default. (Muted alerts are left out where the flash picks
-- them: test_flash.)
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local config = require("lens.hub.config")
local glassesMock = require("glasses")

check(config.check({}).chat == false and config.check({ chat = true }).chat == true, "chat: off by default")
check(select(2, config.check({ chat = "yes" })):find("chat must be", 1, true), "chat is true or false")

local function agents()
  return {
    R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
      m:beginCycle()
      if now >= 20 then m:alert("power:mac2", "bad", "Macerator 2: no power") end
      if now >= 20 then m:alert("idle:wash1", "warn", "Washer 1 idle") end
      if now >= 40 then for i = 1, 7 do m:alert("power:m" .. i, "bad", "Machine " .. i .. ": no power") end end
    end },
    R.agent{ node = "power-room", role = "lumen", cycle = function(m, now)
      m:beginCycle()
      if now >= 20 then m:alert("reactor:N-3", "bad", "Reactor N-3: fault signal") end
    end },
  }
end

-- Bob's HUD shows only power-room's alerts.
local CFG = [[return { chat = true, hud = { blocks = { { elements = { { kind = "alerts", count = 3 } } } } } }]]
local A, B = glassesMock.new(), glassesMock.new()
B.proxy.getBindPlayers = function() return "Bob" end
local function texts(G, who)
  local out = {}
  for _, s in ipairs(G.sent) do if s[1] == who then out[#out + 1] = s[2] end end
  return table.concat(out, "\n")
end

M.setTime(0)
local seen = {}
local step = 0
local ok, err, dir = R.run{ cfg = CFG, agents = agents(), keyboard = true, terminals = { gl000001 = A, gl000002 = B },
  script = function(t)
  if t < 5 then return nil end
  step = step + 1
  if step == 1 then return R.tap(" HUD ", "Bob", 1) end
  if step == 2 then return R.tap("NODES: all", "Bob", 3) end           -- prism-*? no: cycle to power-room
  if step == 3 then
    if not M.find("NODES: power-room", 3) then step = 2; return R.tap("NODES: ", "Bob", 3) end
    return R.tap("DONE", "Bob", 1)
  end
  if t < 30 then step = step - 1; return nil end
  if step == 4 then
    seen.aaron = texts(A, "Aaron")
    seen.bob = texts(B, "Bob")
    return nil
  end
  if t < 50 then step = step - 1; return nil end
  seen.aaronLater = texts(A, "Aaron")
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.aaron:find("[LENS] BAD Macerator 2: no power · prism-ore", 1, true)
  and seen.aaron:find("[LENS] BAD Reactor N-3: fault signal · power-room", 1, true), "each new BAD alert reaches Aaron's chat")
check(not seen.aaron:find("Washer", 1, true), "WARNs don't")
check(seen.bob:find("Reactor N-3", 1, true) and not seen.bob:find("Macerator", 1, true),
  "Bob, whose HUD shows only power-room, gets only its alerts")
local _, n = seen.aaronLater:gsub("%[LENS%]", "")
check(n == 5, ("at most 5 a minute (%d)"):format(n))
local _ = dir

-- Off by default.
A = glassesMock.new()
ok = R.run{ cfg = "return {}", dir = "off", agents = agents(), terminals = { gl000001 = A }, script = function(t)
  if t < 30 then return nil end
  return "stop"
end }
check(ok and #A.sent == 0, "without chat = true, nothing is sent")

H.done()
