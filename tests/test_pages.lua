-- test_pages.lua: the dashboard's pages and the alert log, through lens-hub: + PAGE named on the keyboard,
-- panels added to one page, tabs on the dashboard switching what's shown, deleting a page; the LOG page with
-- alerts happening now and ones that have ended; both on a 3 x 4 screen. (board pages and alerts:history on
-- their own: test_board, test_hub.) Previews: make screens.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local R = require("hubrun")(H)
local check = H.check
local files = require("lens.files")

-- A machine that's down from t = 10 to t = 40, and an LSC.
local function agents()
  local ore = R.agent{ node = "prism-ore", role = "prism", cycle = function(m, now)
    m:beginCycle()
    m:gauge("prism_backlog_items", "b", "items"):set(4200, { process = "ore" })
    if now >= 10 and now < 40 then m:alert("machine:mac2", "bad", "mac2: no power") end
  end }
  local power = R.agent{ node = "power-room", role = "lumen", cycle = function(m)
    m:gauge("lumen_fill_ratio", "f"):set(0.95)
  end }
  return { ore, power }
end

local CFG = [[return { panels = {
  { label = "Ore backlog", value = "sum(prism_backlog_items)", unit = "items" },
  { label = "Power", value = "lumen_fill_ratio", format = "percent" },
} }]]

M.setTime(0)
M.resize(160, 50)
local seen = {}
local step = 0
local K = require("lens.hub.textfield").KEYS
local ok, err, dir = R.run{ cfg = CFG, agents = agents(), keyboard = true, script = function(t)
  if t < 3 then return nil end
  step = step + 1
  if step == 1 then seen.noTabs = not M.find(" Main ", 2); return R.tap(" EDIT ", "Aaron", 1) end
  if step == 2 then seen.editPages = M.find("PAGES", 1) and M.find(" Main ", 1) and M.find("ON MAIN (2)", 1)
    return R.tap("+ PAGE", "Aaron", 1) end
  if step == 3 then
    seen.naming = M.find("Page 2▏", 1) ~= nil
    for _ = 1, 6 do R.queue(R.key(K.back, "Aaron")) end
    R.queue(R.keys("Power", "Aaron"))
    R.queue(R.key(K.enter, "Aaron"))
    return nil
  end
  if step == 4 then
    seen.named = M.find(" Power ", 1) and M.find("ON POWER (0)", 1) and M.find("LIBRARY (2)", 1)
    local _, y = M.find("Power", 4, 80)                      -- the library's row for the view Power
    return { "touch", "screen", M.find(" + ", y), y, 0, "Aaron" }
  end
  if step == 5 then seen.added = M.find("ON POWER (1)", 1) ~= nil; return R.tap("DONE", "Aaron", 1) end
  if step == 6 then
    seen.tabs = M.find(" Main ", 2) and M.find(" Power ", 2) and M.find("Ore backlog", 3) and M.find("95%", 3)
    H.screen("pages")
    return R.tap(" Power ", "Bob", 2)                       -- anyone can switch pages
  end
  if step == 7 then seen.switched = M.find("95%", 3) and not M.find("Ore backlog", 3); return nil end
  if t < 45 then
    if t >= 15 and not seen.logNow then
      seen.logNow = true
      return R.tap(" LOG ", "Aaron", 1)
    end
    if seen.logNow and not seen.nowChecked then
      seen.nowChecked = true
      seen.now = M.find("Alert log", 1) and M.find("NOW (1)", 1) and M.find("mac2: no power", 3) and M.find("for ", 3)
        and M.find("EARLIER (0)", 1)
      return R.tap("DONE", "Aaron", 1)
    end
    return nil
  end
  if not seen.logLater then seen.logLater = true; return R.tap(" LOG ", "Aaron", 1) end
  if not seen.later then
    seen.later = M.find("NOW (0)", 1) and M.find("EARLIER (1)", 1) and M.find("lasted", 3) and M.find("mac2: no power", 3)
    H.screen("log")
    return R.tap("DONE", "Aaron", 1)
  end
  if not seen.deleting then
    seen.deleting = true
    return R.tap(" EDIT ", "Aaron", 1)
  end
  if not seen.deleted then
    seen.deleted = true
    return R.tap("DELETE PAGE", "Aaron", 1)                  -- the page being edited: Power, the one shown
  end
  if not seen.checkedDelete then
    seen.checkedDelete = true
    seen.afterDelete = M.find("ON MAIN (2)", 1) and not M.row(2):find(" Power ", 1, true)   -- the page row
    return R.tap("DONE", "Aaron", 1)
  end
  seen.back = M.find("Ore backlog", 3) and not M.find(" Main ", 2)
  return "stop"
end }
check(ok, "lens-hub runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.noTabs, "one page: no tabs")
check(seen.editPages and seen.naming and seen.named, "EDIT: + PAGE asks for a name; typing and Enter name it")
check(seen.added, "a view from the library goes on the page being edited")
check(seen.tabs, "the dashboard shows tabs; Main keeps its panels")
check(seen.switched, "a tab shows that page's panels (anyone may switch)")
check(seen.now, "LOG: an alert happening now, and for how long")
check(seen.later, "LOG: once it clears it's under EARLIER, with how long it lasted")
check(seen.afterDelete and seen.back, "DELETE PAGE: back to one page, no tabs, Main shown")
local saved = files.loadTable(dir .. "/lens-board.cfg")
check(saved and #saved.pages == 1 and saved.pages[1].name == "Main" and #saved.pages[1].panels == 2,
  "lens-board.cfg: pages")

-- A 3 x 4 screen: tabs, the EDIT page's page row, and the log fit.
M.setTime(0)
M.resize(73, 50)
M.aspect = { 3, 4 }
M.oob = 0
step = 0
ok = R.run{ cfg = CFG, dir = "portrait", agents = agents(), keyboard = true, script = function(t)
  if t < 15 then return nil end
  step = step + 1
  if step == 1 then return R.tap(" EDIT ", "Aaron", 1) end
  if step == 2 then return R.tap("+ PAGE", "Aaron", 1) end
  if step == 3 then R.queue(R.key(K.enter, "Aaron")); return nil end
  if step == 4 then H.screen("edit-pages-portrait"); return R.tap("DONE", "Aaron", 1) end
  if step == 5 then seen.portraitTabs = M.find(" Page 2 ", 2) and M.find(" LOG ", 1); return R.tap(" LOG ", "Aaron", 1) end
  seen.portraitLog = M.find("NOW (1)", 1) ~= nil
  H.screen("log-portrait")
  return "stop"
end }
check(ok and seen.portraitTabs and seen.portraitLog and M.oob == 0, "tabs, the page row and the log fit a 3 x 4 screen")
M.aspect = nil
M.resize(160, 50)

H.done()
