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

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "Avante", "AvanteInput" },
  callback = function(args)
    local opts = { buffer = args.buf, silent = true, noremap = false }

    -- C-h/C-l のみマッピング（C-j/C-k は Avante のデフォルト機能 switch_windows を使用）
    vim.keymap.set("i", "<C-h>", "<Esc><C-w>h", opts)
    vim.keymap.set("i", "<C-l>", "<Esc><C-w>l", opts)
    vim.keymap.set("n", "<C-h>", "<C-w>h", opts)
    vim.keymap.set("n", "<C-l>", "<C-w>l", opts)
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "AvanteSelectedFiles" },
  callback = function(args)
    local opts = { buffer = args.buf, silent = true, noremap = false }

    -- AvanteSelectedFiles にも Avante の switch_windows 機能を使用
    vim.keymap.set("n", "<C-h>", "<C-w>h", opts)
    vim.keymap.set("n", "<C-l>", "<C-w>l", opts)
  end,
})

-- Avante チャットウィンドウに移動した際に入力欄にフォーカスを当てる
-- （Avante 関連バッファ以外から移動した場合のみ）
local last_avante_ft = nil
vim.api.nvim_create_autocmd("BufLeave", {
  pattern = "*",
  callback = function()
    last_avante_ft = vim.bo.filetype
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*",
  callback = function()
    -- 現在のバッファが Avante filetype の場合
    if vim.bo.filetype == "Avante" then
      -- 移動元が Avante 関連バッファでない場合のみ、AvanteInput にフォーカスを移動
      if last_avante_ft ~= "Avante" and last_avante_ft ~= "AvanteInput" and last_avante_ft ~= "AvanteSelectedFiles" then
        -- AvanteInput バッファを探してフォーカスを移動
        vim.schedule(function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "AvanteInput" then
              vim.api.nvim_set_current_win(win)
              vim.cmd("startinsert")
              break
            end
          end
        end)
      end
    end
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
