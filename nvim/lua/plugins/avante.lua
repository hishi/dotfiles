return { -- avante.nvimの設定（一部省略）
  {
    "yetone/avante.nvim",
    opts = {
      provider = "copilot",
      auto_suggestions_provider = nil,
      behaviour = {
        auto_focus_sidebar = false,
        auto_set_keymaps = true,
        auto_add_current_file = true,
        enable_token_counting = true,
      },
      input = {
        provider = "snacks",
        provider_opts = {
          title = "Avante",
        },
      },
      selector = {
        provider = "snacks",
      },
      mappings = {
        ask = "<leader>aa",
        new_ask = "<leader>an",
        edit = "<leader>ae",
        refresh = "<leader>ar",
        focus = "<leader>af",
        stop = "<leader>aS",
        toggle = {
          default = "<leader>at",
          suggestion = "<leader>as",
          repomap = "<leader>aR",
        },
        files = {
          add_current = "<leader>ac",
          add_all_buffers = "<leader>aB",
        },
        select_model = "<leader>am",
        select_history = "<leader>ah",
        sidebar = {
          switch_windows = "<C-j>",
          reverse_switch_windows = "<C-k>",
          apply_all = "A",
          apply_cursor = "a",
          retry_user_request = "r",
          edit_user_request = "e",
          add_file = "@",
          remove_file = "d",
          close = { "q", "<Esc>" },
        },
      },
      windows = {
        position = "right",
        width = 38,
        wrap = true,
        sidebar_header = {
          enabled = true,
          align = "center",
          rounded = true,
          include_model = true,
        },
        input = {
          height = 10,
        },
        ask = {
          floating = false,
          start_insert = true,
          border = "rounded",
        },
        edit = {
          border = "rounded",
          start_insert = true,
        },
      },
      providers = {
        copilot = {
          endpoint = "https://api.githubcopilot.com",
          -- model = "claude-sonnet-4.5",
          model = "gpt-5-mini",
        },
      },
    },
    config = function(_, opts)
      require("avante").setup(opts)
    end,
  },
}
