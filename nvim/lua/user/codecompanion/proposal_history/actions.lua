local M = {}

local api = vim.api

local function current_entry_for_row(entry_spans)
  local row0 = api.nvim_win_get_cursor(0)[1] - 1
  for _, span in ipairs(entry_spans) do
    if row0 >= span.start_row0 and row0 <= span.end_row0 then
      return span
    end
  end
  return nil
end

---@param opts { history_buf: number, win: number, entry_spans: table[], filepath: string }
function M.attach(opts)
  local history_buf = opts.history_buf
  local win = opts.win
  local entry_spans = opts.entry_spans or {}
  local filepath = opts.filepath

  vim.keymap.set("n", "q", function()
    pcall(api.nvim_win_close, win, true)
  end, { buffer = history_buf, desc = "Close", nowait = true, silent = true })

  vim.keymap.set("n", "<cr>", function()
    local span = current_entry_for_row(entry_spans)
    if not span or not span.entry then
      return
    end
    require("user.codecompanion.tools.insert_edit_into_file").show_pending_diff(span.entry, {
      title = span.title,
      ft = span.entry.ft,
      filepath = filepath,
      read_only = true,
    })
  end, { buffer = history_buf, desc = "Open diff view", nowait = true, silent = true })

  vim.keymap.set("n", "ga", function()
    vim.notify("CodeCompanion: proposal history is read-only (use ga/gr in the edit buffer)", vim.log.levels.INFO)
  end, { buffer = history_buf, desc = "Read-only", nowait = true, silent = true })

  vim.keymap.set("n", "gr", function()
    vim.notify("CodeCompanion: proposal history is read-only (use ga/gr in the edit buffer)", vim.log.levels.INFO)
  end, { buffer = history_buf, desc = "Read-only", nowait = true, silent = true })
end

return M
