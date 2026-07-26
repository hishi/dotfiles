-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lua" },
  callback = function()
    vim.b.autoformat = false
  end,
})

-- quickfix window: keep focus in qf while previewing the entry under cursor with j/k
vim.api.nvim_create_autocmd("FileType", {
  pattern = "qf",
  callback = function(args)
    local opts = { buffer = args.buf, silent = true, noremap = true }

    local function qf_follow(step)
      local qf_win = vim.api.nvim_get_current_win()
      vim.cmd("normal! " .. step)
      vim.cmd("silent! .cc")
      if vim.api.nvim_win_is_valid(qf_win) then
        vim.api.nvim_set_current_win(qf_win)
      end
    end

    vim.keymap.set("n", "j", function()
      qf_follow("j")
    end, opts)
    vim.keymap.set("n", "k", function()
      qf_follow("k")
    end, opts)
  end,
})

-- -- 引数なしで起動したときに Yazi を開く
-- vim.api.nvim_create_autocmd("VimEnter", {
--   callback = function()
--     -- 引数がある場合（ファイル名やディレクトリ指定あり）は何もしない
--     if vim.fn.argc() > 0 or vim.api.nvim_buf_get_name(0) ~= "" then
--       return
--     end
--     -- Yazi を起動
--     -- yazi.nvim を使っている場合、以下の関数を呼び出します
--     require("yazi").yazi()
--   end,
-- })
--
