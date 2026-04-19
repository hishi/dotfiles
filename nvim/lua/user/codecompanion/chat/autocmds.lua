local M = {}

function M.setup()
  local aug = vim.api.nvim_create_augroup("user.codecompanion", { clear = true })

  require("user.codecompanion.highlights").setup()
  require("user.codecompanion.pending_edits").setup()

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatCreated",
    group = aug,
    callback = function(args)
      local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
      if not chat then
        return
      end

      require("user.codecompanion.chat.context").ensure_current_file_context(chat)
      vim.schedule(function()
        require("user.codecompanion.chat.context").set_chat_root_cwd(chat)
      end)

      require("user.codecompanion.chat.ui").setup_generating_indicator(chat)
    end,
  })
end

return M
