return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    explorer = {
      enabled = false,
    },
    picker = {
      layout = {
        cycle = false,
      },
      sources = {
        explorer = {
          layout = {
            cycle = false,
          },
        },
        -- ここを追加
        grep = {
          actions = {
            send_to_grug_far = function(picker)
              local search = picker.input.filter.search
              if not search or vim.trim(search) == "" then
                vim.notify("Snacks grep: 検索語が空です", vim.log.levels.WARN)
                return
              end

              picker:close()
              require("grug-far").open({
                prefills = {
                  search = search,
                  paths = picker:cwd(),
                },
              })
            end,
          },
          win = {
            input = {
              keys = {
                ["<C-r>"] = { "send_to_grug_far", mode = { "i", "n" }, nowait = true },
              },
            },
          },
        },
      },
    },
    terminal = {
      win = {
        position = "float",
        width = 0.9,
        height = 0.9,
        border = "rounded",
      },
    },
    lazygit = {
      win = {
        width = 0,
        height = 0,
        border = "none",
      },
    },
    dashboard = {
      -- your dashboard configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below

      enabled = true,
      preset = {
        keys = {
          { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          {
            icon = " ",
            key = "c",
            desc = "Config",
            action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
          },
          { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
    },
  },
}
