local M = {}

local function project_root_for_chat(chat)
  local cwd = vim.fn.getcwd()
  pcall(function()
    if type(LazyVim) == "table" and type(LazyVim.root) == "function" then
      cwd = LazyVim.root({ buf = chat.bufnr }) or cwd
    end
  end)
  return cwd
end

function M.pick_files_into_chat(chat)
  local ok_snacks, snacks = pcall(require, "snacks")
  if not ok_snacks or not snacks or not snacks.picker then
    return vim.notify("snacks.nvim が利用できません", vim.log.levels.WARN)
  end

  local initial_mode = vim.fn.mode():sub(1, 1)
  local cwd = project_root_for_chat(chat)

  local function open_picker()
    snacks.picker.pick("files", {
      cwd = cwd,
      prompt = "CodeCompanion: ",
      main = { current_win = (chat.ui and chat.ui.winnr) or vim.api.nvim_get_current_win() },
      actions = {
        confirm = function(picker)
          local selected = picker:selected({ fallback = true }) or {}
          picker:close()

          local slash = require("codecompanion.interactions.chat.slash_commands")
          vim.iter(selected):each(function(item)
            local file = item.file or item.text
            local item_cwd = item.cwd or cwd
            if not file or file == "" then
              return
            end
            local path = vim.fs.joinpath(item_cwd, file)
            slash.context(chat, "file", {
              path = path,
              description = ("file: %s"):format(file),
            })
          end)

          -- Bring focus back to the chat after selecting file(s)
          local chat_winnr = chat.ui and chat.ui.winnr
          if chat_winnr and vim.api.nvim_win_is_valid(chat_winnr) then
            vim.schedule(function()
              pcall(vim.api.nvim_set_current_win, chat_winnr)
              if initial_mode == "i" then
                pcall(vim.cmd, "startinsert")
              end
            end)
          end

          return true
        end,
      },
    })
  end

  if vim.fn.mode():sub(1, 1) == "i" then
    vim.cmd.stopinsert()
    return vim.schedule(open_picker)
  end

  return open_picker()
end

function M.chat_keymaps()
  return {
    change_adapter = false,
    add_files = {
      description = "[Chat] Add file(s) to context",
      modes = { n = "ga" },
      callback = M.pick_files_into_chat,
    },
  }
end

return M
