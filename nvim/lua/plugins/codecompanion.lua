return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "zbirenbaum/copilot.lua",
      "ravitemer/codecompanion-history.nvim",
    },
    cmd = {
      "CodeCompanion",
      "CodeCompanionActions",
      "CodeCompanionChat",
      "CodeCompanionCmd",
    },
    keys = {
      { "<leader>ccm", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "AI Actions" },
      { "<C-;>", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v", "i" }, desc = "AI Chat Toggle" },
      { "<leader>cca", "<cmd>CodeCompanionChat Add<cr>", mode = { "n", "v" }, desc = "Add to AI Chat" },
    },
    opts = require("user.codecompanion.opts"),
    init = function()
      require("user.codecompanion.commands").setup()
      require("user.codecompanion.chat.autocmds").setup()
    end,
  },
}
