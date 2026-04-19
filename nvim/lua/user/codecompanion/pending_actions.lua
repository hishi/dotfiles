local M = {}

local api = vim.api

local function split_lines(s)
  return vim.split(s or "", "\n", { plain = true })
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

local function each_loaded_buf_for_path(filepath, cb)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) == filepath then
      cb(b)
    end
  end
end

---@param filepath string
function M.accept_all(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return false, "No filepath"
  end

  require("user.codecompanion.pending_edits").remove_all(filepath)

  local tool = require("user.codecompanion.tools.insert_edit_into_file")
  each_loaded_buf_for_path(filepath, function(b)
    pcall(tool.clear_inline_visual, b)
  end)

  return true, nil
end

---@param filepath string
---@param idx integer 1-based pending index to reject to (reject this and newer)
function M.reject_to(filepath, idx)
  if type(filepath) ~= "string" or filepath == "" then
    return false, "No filepath"
  end
  idx = tonumber(idx)
  if not idx then
    return false, "Invalid index"
  end

  local pe = require("user.codecompanion.pending_edits")
  local state = pe.get(filepath)
  local ents = state and state.entries or {}
  if #ents == 0 then
    return false, "No pending"
  end
  if idx < 1 or idx > #ents then
    return false, "Index out of range"
  end

  -- Safety: only allow reject if the on-disk file matches the latest proposed.
  local Path = require("plenary.path")
  local p = Path:new(filepath)
  local current = p:read() or ""
  local latest = ents[#ents] and (ents[#ents].proposed or "") or ""
  if not equivalent_text(current, latest) then
    return false, "File changed since last proposal"
  end

  local restore_content = ents[idx].original or ""
  p:write(restore_content, "w")

  local tool = require("user.codecompanion.tools.insert_edit_into_file")
  each_loaded_buf_for_path(filepath, function(b)
    pcall(tool.clear_inline_visual, b)
    api.nvim_buf_set_lines(b, 0, -1, false, split_lines(restore_content))
    pcall(api.nvim_set_option_value, "modified", false, { buf = b })
  end)

  pe.truncate(filepath, idx - 1)

  -- If there is still pending (older), rehydrate in the current file buffer if open.
  local file_buf = vim.fn.bufnr(filepath)
  if file_buf ~= -1 and api.nvim_buf_is_valid(file_buf) then
    pcall(function()
      pe.try_restore_for_buf(file_buf)
    end)
  end

  return true, nil
end

return M

