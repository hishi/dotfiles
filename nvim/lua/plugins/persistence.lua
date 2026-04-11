return {
  {
    "folke/persistence.nvim",
    init = function()
      vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("auto_restore_session", { clear = true }),
        once = true,
        callback = function()
          local no_args = vim.fn.argc() == 0
          local no_stdin = vim.fn.line2byte("$") == -1
          local is_empty_buffer = vim.api.nvim_buf_get_name(0) == "" and vim.bo.filetype == ""

          if not (no_args and no_stdin and is_empty_buffer) then
            return
          end

          vim.schedule(function()
            require("persistence").load()
          end)
        end,
      })
    end,
  },
}
