return {
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    cmd = { "Obsidian" },
    opts = {
      legacy_commands = false,
      workspaces = {
        {
          name = "main",
          path = "/Users/hishi/Library/Mobile Documents/iCloud~md~obsidian/Documents/hishi",
          strict = true,
        },
      },
      daily_notes = {
        folder = os.date("%Y/%m"),
        date_format = "YYYY-MM-DD",
      },
      footer = {
        enabled = false,
      },
      statusline = {
        enabled = false,
      },
      picker = {
        name = "snacks.picker",
      },
    },
  },
}
