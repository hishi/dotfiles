return { -- avante.nvimの設定（一部省略）
  {
    "yetone/avante.nvim",
    opts = {
      provider = "copilot",
      auto_suggestions_provider = nil,
      providers = {
        copilot = {
          endpoint = "https://api.githubcopilot.com",
          model = "claude-sonnet-4.5",
        },
      },
    },
  },
}
