local M = {}

local api = vim.api

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

local function equivalent_text(a, b)
  if a == b then
    return true
  end
  if not a or not b then
    return false
  end
  if (a .. "\n") == b then
    return true
  end
  if (b .. "\n") == a then
    return true
  end
  return false
end

local function buf_to_text(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

local function get_entries_for_state(st, filepath)
  local bucket = st[filepath]
  if type(bucket) ~= "table" or type(bucket.entries) ~= "table" then
    return {}
  end
  return bucket.entries
end

local function archive_entries(filepath, entries, reason)
  if type(entries) ~= "table" or #entries == 0 then
    return
  end
  local ok, hist = pcall(require, "user.codecompanion.pending_history")
  if not ok or type(hist) ~= "table" or type(hist.append_many) ~= "function" then
    return
  end
  pcall(hist.append_many, filepath, entries, reason)
end

local function new_session_id()
  return tostring(os.time()) .. ":" .. tostring(math.random(100000, 999999))
end

---@param entry { filepath: string, original: string, proposed: string, title?: string, ft?: string, saved_at?: integer }
function M.push(entry)
  if not entry or type(entry.filepath) ~= "string" or entry.filepath == "" then
    return
  end
  entry.filepath = normalize_path(entry.filepath)

  local st = read_state()
  local old_entries = get_entries_for_state(st, entry.filepath)
  local session_id = nil
  if #old_entries > 0 then
    session_id = old_entries[#old_entries].session_id or old_entries[1].session_id
  end
  session_id = session_id or entry.session_id or new_session_id()
  if #old_entries > 0 then
    archive_entries(entry.filepath, old_entries, "superseded")
  end

  entry.session_id = session_id
  entry.id = entry.id or new_session_id()
  st[entry.filepath] = { entries = { entry } }
  write_state(st)
  return entry.id
end

---@param filepath string
---@param reason? string
function M.remove_all(filepath, reason)
  filepath = normalize_path(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return
  end
  local st = read_state()
  local old_entries = get_entries_for_state(st, filepath)
  if #old_entries == 0 and st[filepath] == nil then
    return
  end
  archive_entries(filepath, old_entries, reason or "cleared")
  st[filepath] = nil
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

---@param filepath string
---@return table|nil
function M.peek(filepath)
  filepath = normalize_path(filepath)
  local v = M.get(filepath)
  if not v or type(v.entries) ~= "table" then
    return nil
  end
  return v.entries[#v.entries]
end

---@param filepath string
---@param reason? string
---@return table|nil
function M.pop(filepath, reason)
  filepath = normalize_path(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return nil
  end
  local st = read_state()
  local entries = get_entries_for_state(st, filepath)
  if #entries == 0 then
    return nil
  end

  local popped = table.remove(entries, #entries)
  archive_entries(filepath, { popped }, reason or "popped")

  if #entries == 0 then
    st[filepath] = nil
  else
    st[filepath] = { entries = entries }
  end
  write_state(st)
  return popped
end

---@param filepath string
---@param keep_n integer
function M.truncate(filepath, keep_n)
  filepath = normalize_path(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return
  end
  keep_n = tonumber(keep_n) or 0
  if keep_n <= 0 then
    M.remove_all(filepath, "truncated")
    return
  end
  if keep_n >= 1 then
    return
  end
end

---@param filepath string
---@param idx integer
---@return table|nil
function M.remove_at(filepath, idx)
  filepath = normalize_path(filepath)
  idx = tonumber(idx)
  if idx ~= 1 then
    return nil
  end
  return M.pop(filepath, "removed")
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
  if vim.bo[bufnr].modified then
    return
  end

  local filepath = api.nvim_buf_get_name(bufnr)
  filepath = normalize_path(filepath)
  if not filepath or filepath == "" then
    return
  end

  local entry = M.peek(filepath)
  if not entry then
    return
  end

  local current = buf_to_text(bufnr)
  if not equivalent_text(current, entry.proposed or "") then
    return
  end

  local tool = require("user.codecompanion.tools.insert_edit_into_file")
  if type(tool.rehydrate_inline_diff) == "function" then
    tool.rehydrate_inline_diff(bufnr, entry.original or "", entry.proposed or "", {
      filepath = filepath,
      title = entry.title,
      ft = entry.ft,
      reject_to = entry.original or "",
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
