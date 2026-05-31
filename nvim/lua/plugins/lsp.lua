local servers = {
  "vtsls",
  "pyright",
  "ruff",
  "terraformls",
  -- "ruby_lsp",
  "herb_ls",
}

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      for _, server in ipairs(servers) do
        opts.servers[server] = opts.servers[server] or {}
      end

      opts.servers["*"] = opts.servers["*"] or {}
      opts.servers["*"].keys = opts.servers["*"].keys or {}
      table.insert(opts.servers["*"].keys, {
        "gd",
        function()
          Snacks.picker.lsp_definitions({ auto_confirm = false })
        end,
        desc = "Goto Definition (Picker)",
        has = "definition",
      })
    end,
  },
}
