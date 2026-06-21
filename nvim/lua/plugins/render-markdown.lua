return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    cmd = { "RenderMarkdown" },
    ft = { "markdown", "markdown.mdx", "Avante", "codecompanion" },
    keys = {
      { "<leader>op", "<cmd>RenderMarkdown preview<cr>", ft = "markdown", desc = "Markdown Preview (Split)" },
    },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-mini/mini.icons",
    },
    opts = {
      enabled = false,
      file_types = { "markdown", "Avante", "codecompanion" },
    },
  },
}
