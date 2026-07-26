return {
  "CopilotC-Nvim/CopilotChat.nvim",
  dependencies = {
    "zbirenbaum/copilot.lua",
    "nvim-lua/plenary.nvim",
  },
  cmd = { "CopilotChat" },
  ft = { "gitcommit" },
  keys = {
    { "<C-;>", "<cmd>CopilotChatToggle<cr>", mode = { "n", "v", "i" }, desc = "AI Chat Toggle" },
  },
  opts = {
    model = "claude-sonnet-4.5",
    window = {
      layout = "float",
      width = 0.9,
      height = 0.9,
      border = "rounded",
    },
  },
  init = function()
    require("user.copilotchat.autocmds").setup()
  end,
}
