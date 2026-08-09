-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local gitcommit_swap_group = vim.api.nvim_create_augroup("user.gitcommit.swap", { clear = true })

vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPre" }, {
  pattern = "COMMIT_EDITMSG",
  group = gitcommit_swap_group,
  callback = function(args)
    vim.bo[args.buf].swapfile = false
  end,
})

vim.api.nvim_create_autocmd("SwapExists", {
  pattern = "COMMIT_EDITMSG",
  group = gitcommit_swap_group,
  callback = function()
    vim.v.swapchoice = "e"
  end,
})

local function map_copilot_accept()
  vim.keymap.set("i", "<C-f>", function()
    local suggestion = vim.fn["copilot#GetDisplayedSuggestion"]()
    if type(suggestion) == "table" and suggestion.text and suggestion.text ~= "" then
      vim.defer_fn(function()
        pcall(function()
          require("user.gitcommit.copilot").cleanup_after_accept()
        end)
      end, 50)

      return vim.fn["copilot#Accept"]("")
    end

    return vim.api.nvim_replace_termcodes("<Ignore>", true, false, true)
  end, {
    expr = true,
    replace_keycodes = false,
    desc = "Accept Copilot suggestion",
  })
end

vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    vim.schedule(map_copilot_accept)
  end,
})
