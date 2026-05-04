return {
  "gbprod/yanky.nvim",
  opts = {},
  keys = {
    {
      "<leader>p",
      function()
        Snacks.picker.yanky()
      end,
      mode = { "n", "x" },
      desc = "Open Yank History",
    },
  },
}
