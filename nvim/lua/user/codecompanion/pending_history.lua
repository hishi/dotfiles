local M = {}

local MAX_ENTRIES_PER_FILE = 100

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return path
  end
  local rp = vim.uv.fs_realpath(path)
  if type(rp) == "string" and rp ~= "" then
    return rp
  end
  return path
end

local function state_path()
  local dir = vim.fn.stdpath("state") .. "/codecompanion"
  vim.fn.mkdir(dir, "p")
  return dir .. "/pending_history.json"
end

local function read_state()
  local p = state_path()
  local f = io.open(p, "r")
  if not f then
    return {}
  end
  local ok, content = pcall(function()
    return f:read("*a")
  end)
  f:close()
  if not ok or not content or content == "" then
    return {}
  end
  local ok2, decoded = pcall(vim.json.decode, content)
  if not ok2 or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

local function write_state(tbl)
  local p = state_path()
  local f = assert(io.open(p, "w"))
  f:write(vim.json.encode(tbl))
  f:close()
end

local function normalize_entries(v)
  if type(v) ~= "table" then
    return {}
  end
  if type(v.entries) == "table" then
    return v.entries
  end
  if v.original and v.proposed then
    return { v }
  end
  return {}
end

local function trim_entries(entries)
  while #entries > MAX_ENTRIES_PER_FILE do
    table.remove(entries, 1)
  end
end

---@param filepath string
---@param entries table[]
---@param reason? string
function M.append_many(filepath, entries, reason)
  filepath = normalize_path(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return
  end
  if type(entries) ~= "table" or #entries == 0 then
    return
  end

  local st = read_state()
  local target = normalize_entries(st[filepath])

  for _, e in ipairs(entries) do
    if type(e) == "table" and e.original ~= nil and e.proposed ~= nil then
      local copy = vim.deepcopy(e)
      copy.archived_at = os.time()
      copy.archived_reason = reason or "archived"
      table.insert(target, copy)
    end
  end

  trim_entries(target)
  st[filepath] = { entries = target }
  write_state(st)
end

---@param filepath string
---@return table|nil
function M.get(filepath)
  filepath = normalize_path(filepath)
  local st = read_state()
  local v = st[filepath]
  if type(v) == "table" and type(v.entries) == "table" then
    return v
  end
  return nil
end

return M
