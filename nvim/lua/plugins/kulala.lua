return {
  "mistweaverco/kulala.nvim",
  keys = {
    -- { "<leader>Rs", desc = "Send request" },
    -- { "<leader>Ra", desc = "Send all requests" },
    -- { "<leader>Rb", desc = "Open scratchpad" },
  },
  ft = {"http", "rest"},
  opts = {
    global_keymaps = true,
    global_keymaps_prefix = "<leader>R",
    kulala_keymaps_prefix = "<leader>k",
    kulala_keymaps = {
      ["Previous response"] = {
        "H",
        function()
          require("kulala.ui").show_previous()
        end,
      },
      ["Next response"] = {
        "L",
        function()
          require("kulala.ui").show_next()
        end,
      },
    },
  },
}
