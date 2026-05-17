return {
  "MagicDuck/grug-far.nvim",
  opts = function(_, opts)
    opts = opts or {}
    opts.headerMaxWidth = 120
    opts.windowCreationCommand = "botright vsplit"
    opts.keymaps = vim.tbl_deep_extend("force", opts.keymaps or {}, {
      replace = { n = "gr" },
      qflist = { n = "gq" },
      syncLocations = { n = "gs" },
      syncLine = { n = "gl" },
      close = { n = "gc" },
      historyOpen = { n = "gt" },
      historyAdd = { n = "ga" },
      refresh = { n = "gf" },
      openLocation = { n = "go" },
      abort = { n = "gb" },
      toggleShowCommand = { n = "gw" },
      swapEngine = { n = "ge" },
      previewLocation = { n = "gi" },
      swapReplacementInterpreter = { n = "gx" },
      applyNext = { n = "gj" },
      applyPrev = { n = "gk" },
      syncNext = { n = "gn" },
      syncPrev = { n = "gp" },
      syncFile = { n = "gv" },
    })
    return opts
  end,
  init = function()
    local function set_grug_far_hl()
      if vim.o.background ~= "dark" then
        return
      end

      vim.api.nvim_set_hl(0, "GrugFarResultsMatch", { bg = "#6B4F00", fg = "#FFF4B5" })
      vim.api.nvim_set_hl(0, "GrugFarResultsMatchAdded", { bg = "#1F6A41", fg = "#E8FFEF" })
      vim.api.nvim_set_hl(0, "GrugFarResultsMatchRemoved", { bg = "#7A2438", fg = "#FFE8EE" })
    end

    local group = vim.api.nvim_create_augroup("user-grug-far-highlights", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = group,
      callback = set_grug_far_hl,
    })
    set_grug_far_hl()
  end,
}
