return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot", -- :Copilotコマンドが実行されたときにプラグインを読み込む
  build = ":Copilot auth", -- プラグインロード後左記のコマンドを実行
  event = "BufReadPost", -- ファイルが読み込まれた後にプラグインをロード. https://vim-jp.org/vimdoc-ja/autocmd.html
  config = function()
    require("copilot").setup({
      suggestion = {
        enabled = true,
        auto_trigger = true,
        debounce = 75,
        keymap = {
          accept = "<C-l>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
      filetypes = {
        codecompanion = false,
        codecompanion_input = false,
        gitcommit = true,
      },
    })
  end,
}
