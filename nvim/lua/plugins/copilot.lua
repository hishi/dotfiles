return {
  "github/copilot.vim",
  lazy = false,
  init = function()
    vim.g.copilot_no_tab_map = true
    vim.g.copilot_version = false
    vim.g.copilot_filetypes = {
      gitcommit = true,
    }
  end,
}
