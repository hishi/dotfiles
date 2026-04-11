-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("t", "<C-[>", "<C-\\><C-n>", { noremap = true })
vim.keymap.set("n", "<leader>fo", require("oil").toggle_float, { desc = "Open oil in float" })

vim.keymap.set("n", "c", '"_c', { noremap = true })
vim.keymap.set("x", "c", '"_c', { noremap = true })
vim.keymap.set("n", "C", '"_C', { noremap = true })
vim.keymap.set("n", "s", '"_s', { noremap = true })
vim.keymap.set("x", "S", '"_S', { noremap = true })
