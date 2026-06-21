return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    cmd = { "RenderMarkdown" },
    ft = { "markdown", "markdown.mdx", "Avante", "codecompanion" },
    keys = {
      {
        "<leader>op",
        function()
          local rm = require("render-markdown")
          rm.enable()
          rm.preview()
        end,
        ft = "markdown",
        desc = "Markdown Preview (Split)",
      },
    },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-mini/mini.icons",
    },
    opts = {
      enabled = false,
      file_types = { "markdown", "Avante", "codecompanion" },
      pipe_table = {
        preset = "round",
        style = "full",
        cell = "padded",
        min_width = 8,
        border_virtual = true,
      },
      heading = {
        -- Keep H1/H2 readable without the visual indent/padded full-line background.
        sign = false,
        position = "inline",
        width = "block",
        left_margin = 0,
        left_pad = 0,
        right_pad = 0,
        icons = { "H1 ", "H2 ", "H3 ", "H4 ", "H5 ", "H6 " },
      },
    },
  },
}
