--[[ lens.files: reading and writing the files LENS keeps.

  exists(path)                 true if the file can be opened
  read(path)                   the whole file as text, or nil
  loadTable(path)              run a Lua file that returns a table -> table | nil, err (err nil when missing)
  writeAtomic(path, text)      write path.new, then swap it in -> true | false, err
  saveWithBackup(path, text)   keep the old contents as path.bak, then writeAtomic -> true | false, err
]]

local F = {}

function F.exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

function F.read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function F.loadTable(path)
  local text = F.read(path)
  if not text then return nil end
  local chunk, err = load(text, "=" .. path, "t", {})
  if not chunk then return nil, err end
  local ok, t = pcall(chunk)
  if not ok then return nil, tostring(t) end
  if type(t) ~= "table" then return nil, path .. " doesn't return a table" end
  return t
end

function F.writeAtomic(path, text)
  local tmp = path .. ".new"
  local f, err = io.open(tmp, "w")
  if not f then return false, err end
  f:write(text)
  f:close()
  os.remove(path)
  local ok, why = os.rename(tmp, path)
  if not ok then return false, why end
  return true
end

function F.saveWithBackup(path, text)
  local old = F.read(path)
  if old then
    local ok, err = F.writeAtomic(path .. ".bak", old)
    if not ok then return false, err end
  end
  return F.writeAtomic(path, text)
end

return F
