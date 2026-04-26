local M = {}

local api = vim.api

---@param diff CC.Diff
---@param diff_mod table
---@return CC.Diff
local function build_proposed_first_merged(diff, diff_mod)
  local hunks = diff_mod._diff(diff.from.lines, diff.to.lines) or {}

  local merged_lines = {} ---@type string[]
  local highlights = {} ---@type { row: number, type: "addition"|"deletion"|"change", word_hl?: { col: number, end_col: number }[] }[]
  local from_pos = 1
  local merged_row = 0

  local function add_highlight(merged_row_1, type, word_ranges)
    local entry = { row = merged_row_1, type = type }
    if word_ranges then
      entry.word_hl = word_ranges
    end
    table.insert(highlights, entry)
  end

  local function add_extmark(hunk, merged_row_1, type)
    table.insert(hunk.extmarks, { row = merged_row_1 - 1, col = 0, type = type })
  end

  for _, h in ipairs(hunks) do
    local from_start, from_count, to_start, to_count = unpack(h)
    local kind = from_count > 0 and to_count > 0 and "change" or from_count > 0 and "delete" or "add"

    local stop_at = kind == "add" and from_start or from_start - 1
    while from_pos <= stop_at do
      merged_row = merged_row + 1
      table.insert(merged_lines, diff.from.lines[from_pos])
      from_pos = from_pos + 1
    end

    local hunk = {
      extmarks = {},
      kind = kind,
      pos = { merged_row, 0 },
      from_start = from_start,
      from_count = from_count,
      to_start = to_start,
      to_count = to_count,
    }
    table.insert(diff.hunks, hunk)

    local word_diff_results = {}
    if kind == "change" then
      for i = 0, math.min(from_count, to_count) - 1 do
        local old_line = diff.from.lines[from_start + i] or ""
        local new_line = diff.to.lines[to_start + i] or ""
        local del_ranges, add_ranges = diff_mod._diff_words(old_line, new_line)
        word_diff_results[i] = { del_ranges = del_ranges, add_ranges = add_ranges }
      end
    end

    for i = 0, to_count - 1 do
      merged_row = merged_row + 1
      add_extmark(hunk, merged_row, "addition")
      table.insert(merged_lines, diff.to.lines[to_start + i])
      local word_ranges = word_diff_results[i] and word_diff_results[i].add_ranges or nil
      add_highlight(merged_row, "addition", word_ranges)
    end

    for i = 0, from_count - 1 do
      merged_row = merged_row + 1
      add_extmark(hunk, merged_row, "deletion")
      table.insert(merged_lines, diff.from.lines[from_start + i])
      local word_ranges = word_diff_results[i] and word_diff_results[i].del_ranges or nil
      add_highlight(merged_row, "deletion", word_ranges)
    end

    from_pos = from_pos + from_count
  end

  while from_pos <= #diff.from.lines do
    merged_row = merged_row + 1
    table.insert(merged_lines, diff.from.lines[from_pos])
    from_pos = from_pos + 1
  end

  diff.merged = { lines = merged_lines, highlights = highlights }
  return diff
end

---@param opts { ft?: string, from_lines: string[], to_lines: string[], marker_add?: string, marker_delete?: string }
---@return table diff_mod, table diff_ui_mod, table diff
function M.build_diff_for_ui(opts)
  local diff_mod = require("codecompanion.diff")
  local diff_ui_mod = require("codecompanion.diff.ui")
  local cc_utils = require("codecompanion.utils")

  local bufnr = api.nvim_create_buf(false, true)
  if opts.ft then
    local safe_ft = cc_utils.safe_filetype(opts.ft)
    api.nvim_set_option_value("filetype", safe_ft, { buf = bufnr })
  end

  ---@type CC.Diff
  local diff = {
    bufnr = bufnr,
    ft = opts.ft,
    hunks = {},
    from = { lines = opts.from_lines, text = table.concat(opts.from_lines, "\n") },
    to = { lines = opts.to_lines, text = table.concat(opts.to_lines, "\n") },
    merged = { lines = {}, highlights = {} },
    marker_add = opts.marker_add,
    marker_delete = opts.marker_delete,
  }

  diff = build_proposed_first_merged(diff, diff_mod)
  return diff_mod, diff_ui_mod, diff
end

---@param diff_ui table|nil
function M.remap_diff_accept_reject_keymaps(diff_ui)
  if not (diff_ui and diff_ui.bufnr and api.nvim_buf_is_valid(diff_ui.bufnr)) then
    return
  end

  local shared = require("codecompanion.config").interactions.shared.keymaps
  local function del_map(map)
    if not map or not map.modes then
      return
    end
    for mode, lhs in pairs(map.modes) do
      pcall(vim.keymap.del, mode, lhs, { buffer = diff_ui.bufnr })
    end
  end
  del_map(shared.accept_change)
  del_map(shared.reject_change)

  local diff_keymaps = require("codecompanion.diff.keymaps")
  vim.keymap.set("n", "ga", function()
    diff_keymaps.accept_change.callback(diff_ui)
  end, { buffer = diff_ui.bufnr, desc = "Accept all changes", nowait = true, silent = true })

  vim.keymap.set("n", "gr", function()
    diff_keymaps.reject_change.callback(diff_ui)
  end, { buffer = diff_ui.bufnr, desc = "Reject all changes", nowait = true, silent = true })
end

---@param diff_ui table|nil
function M.set_read_only_diff_keymaps(diff_ui)
  if not (diff_ui and diff_ui.bufnr and api.nvim_buf_is_valid(diff_ui.bufnr)) then
    return
  end
  vim.keymap.set("n", "ga", function()
    vim.notify("CodeCompanion: proposal history diff is read-only", vim.log.levels.INFO)
  end, { buffer = diff_ui.bufnr, desc = "Accept this pending", nowait = true, silent = true })

  vim.keymap.set("n", "gr", function()
    vim.notify("CodeCompanion: proposal history diff is read-only", vim.log.levels.INFO)
  end, { buffer = diff_ui.bufnr, desc = "Reject to here", nowait = true, silent = true })
end

return M
