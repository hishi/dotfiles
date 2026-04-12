-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local open_url = require("config.url_open").open_url

vim.keymap.set("t", "<C-[>", "<C-\\><C-n>", { noremap = true })
vim.keymap.set({ "n", "x" }, "gx", open_url, { desc = "Open URL under cursor" })
vim.keymap.set("t", "gx", "<C-\\><C-n><Cmd>lua require('config.url_open').open_url()<CR>", { desc = "Open URL under cursor" })
vim.keymap.set("n", "<leader>fo", require("oil").toggle_float, { desc = "Open oil in float" })

vim.keymap.set("n", "c", '"_c', { noremap = true })
vim.keymap.set("x", "c", '"_c', { noremap = true })
vim.keymap.set("n", "C", '"_C', { noremap = true })
vim.keymap.set("n", "s", '"_s', { noremap = true })
vim.keymap.set("x", "S", '"_S', { noremap = true })
