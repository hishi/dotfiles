local M = {}

function M.mru_file_buf()
  local best = nil
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local name = info.name
    if name and name ~= "" then
      local ft = vim.api.nvim_get_option_value("filetype", { buf = info.bufnr })
      if ft ~= "codecompanion" and ft ~= "codecompanion_input" then
        if not best or (info.lastused or 0) > (best.lastused or 0) then
          best = info
        end
      end
    end
  end
  return best
end

function M.set_chat_root_cwd(chat)
  local best = M.mru_file_buf()
  local cwd = vim.fn.getcwd()
  pcall(function()
    if best and type(LazyVim) == "table" and type(LazyVim.root) == "function" then
      cwd = LazyVim.root({ buf = best.bufnr }) or cwd
    end
  end)

  local winnr = chat.ui and chat.ui.winnr
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_call(winnr, function()
      vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
    end)
  end
end

function M.ensure_current_file_context(chat)
  local best = M.mru_file_buf()
  if not best then
    return
  end

  local path = best.name
  for _, item in ipairs(chat.context_items or {}) do
    if item.path == path then
      return
    end
  end

  local slash = require("codecompanion.interactions.chat.slash_commands")
  slash.context(chat, "file", { path = path, description = "auto: current file" })
end

return M
