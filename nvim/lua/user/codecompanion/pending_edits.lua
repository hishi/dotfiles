local M = {}

local api = vim.api

local function state_path()
  local dir = vim.fn.stdpath("state") .. "/codecompanion"
  vim.fn.mkdir(dir, "p")
  return dir .. "/pending_edits.json"
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
  -- Backward compat: old format was { [filepath] = entry }
  for fp, v in pairs(decoded) do
    if type(v) == "table" and v.original and v.proposed then
      decoded[fp] = { entries = { v } }
    end
  end
  return decoded
end

local function write_state(tbl)
  local p = state_path()
  local f = assert(io.open(p, "w"))
  f:write(vim.json.encode(tbl))
  f:close()
end

---@param entry { filepath: string, original: string, proposed: string, title?: string, ft?: string, saved_at?: integer }
function M.push(entry)
  if not entry or type(entry.filepath) ~= "string" or entry.filepath == "" then
    return
  end
  local st = read_state()
  st[entry.filepath] = st[entry.filepath] or { entries = {} }
  st[entry.filepath].entries = st[entry.filepath].entries or {}
  entry.id = entry.id or (tostring(os.time()) .. ":" .. tostring(math.random(100000, 999999)))
  table.insert(st[entry.filepath].entries, entry)
  write_state(st)
  return entry.id
end

---@param filepath string
function M.remove_all(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return
  end
  local st = read_state()
  if st[filepath] == nil then
    return
  end
  st[filepath] = nil
  write_state(st)
end

---@param filepath string
---@return table|nil
function M.get(filepath)
  local st = read_state()
  local v = st[filepath]
  if type(v) == "table" and v.entries then
    return v
  end
  return nil
end

---@param filepath string
---@return table|nil
function M.peek(filepath)
  local v = M.get(filepath)
  if not v or type(v.entries) ~= "table" then
    return nil
  end
  return v.entries[#v.entries]
end

---@param filepath string
---@return table|nil
function M.pop(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return nil
  end
  local st = read_state()
  local v = st[filepath]
  if not v or type(v) ~= "table" or type(v.entries) ~= "table" or #v.entries == 0 then
    return nil
  end
  local popped = table.remove(v.entries, #v.entries)
  if #v.entries == 0 then
    st[filepath] = nil
  else
    st[filepath] = v
  end
  write_state(st)
  return popped
end

---@param filepath string
---@param keep_n integer
function M.truncate(filepath, keep_n)
  if type(filepath) ~= "string" or filepath == "" then
    return
  end
  keep_n = tonumber(keep_n) or 0
  local st = read_state()
  local v = st[filepath]
  if not v or type(v) ~= "table" or type(v.entries) ~= "table" then
    return
  end
  if keep_n <= 0 then
    st[filepath] = nil
    write_state(st)
    return
  end
  if keep_n >= #v.entries then
    return
  end
  while #v.entries > keep_n do
    table.remove(v.entries, #v.entries)
  end
  st[filepath] = v
  write_state(st)
end

---@param filepath string
---@param proposed string
---@return table|nil, integer|nil
local function find_by_proposed(filepath, proposed)
  local v = M.get(filepath)
  if not v or type(v.entries) ~= "table" then
    return nil, nil
  end
  for i = #v.entries, 1, -1 do
    if equivalent_text(v.entries[i].proposed or "", proposed or "") then
      return v.entries[i], i
    end
  end
  return nil, nil
end

local function buf_to_text(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

local function equivalent_text(a, b)
  if a == b then
    return true
  end
  if not a or not b then
    return false
  end
  -- Be tolerant about a single trailing newline difference because CodeCompanion's
  -- file writer preserves the original file's trailing newline behavior.
  if (a .. "\n") == b then
    return true
  end
  if (b .. "\n") == a then
    return true
  end
  return false
end

---@param bufnr number
function M.try_restore_for_buf(bufnr)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.b[bufnr].__user_codecompanion_inline_diff then
    return
  end
  if vim.bo[bufnr].buftype ~= "" then
    return
  end
  local filepath = api.nvim_buf_get_name(bufnr)
  if not filepath or filepath == "" then
    return
  end

  local entry = M.peek(filepath)
  if not entry or type(entry) ~= "table" then
    return
  end
  if vim.bo[bufnr].modified then
    return
  end

  local current = buf_to_text(bufnr)
  if not equivalent_text(current, entry.proposed or "") then
    -- The file/buffer may match an older pending entry (e.g. user rejected once).
    local match, idx = find_by_proposed(filepath, current)
    if not match then
      return
    end
    entry = match
    -- Drop any newer entries that no longer match on disk.
    local st = read_state()
    if st[filepath] and st[filepath].entries and idx then
      while #st[filepath].entries > idx do
        table.remove(st[filepath].entries, #st[filepath].entries)
      end
      write_state(st)
    end
  end

  local tool = require("user.codecompanion.tools.insert_edit_into_file")
  if type(tool.rehydrate_inline_diff) == "function" then
    tool.rehydrate_inline_diff(bufnr, entry.original, entry.proposed, {
      filepath = filepath,
      title = entry.title,
      ft = entry.ft,
    })
    vim.notify(("CodeCompanion: restored pending choice for %s"):format(vim.fn.fnamemodify(filepath, ":.")), vim.log.levels.INFO)
  end
end

function M.setup()
  local aug = api.nvim_create_augroup("user.codecompanion.pending_edits", { clear = true })
  api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
    group = aug,
    callback = function(args)
      pcall(M.try_restore_for_buf, args.buf)
    end,
  })
end

return M
