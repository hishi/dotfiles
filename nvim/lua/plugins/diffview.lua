local function jump_file_entry(offset)
  local view = require("diffview.lib").get_current_view()
  if not view or not view.panel or type(view.panel.ordered_file_list) ~= "function" then
    return
  end

  local files = view.panel:ordered_file_list()
  if not files or #files == 0 then
    return
  end

  local cur = view.panel.cur_file
  local cur_idx = 0

  if cur then
    for i, file in ipairs(files) do
      if file == cur then
        cur_idx = i
        break
      end
    end
  end

  local count = vim.v.count1 or 1
  local target_idx

  if cur_idx == 0 then
    target_idx = offset > 0 and 1 or #files
  else
    target_idx = math.max(1, math.min(#files, cur_idx + (offset * count)))
  end

  local target = files[target_idx]
  if target and target ~= cur then
    view:set_file(target, false, true)
  end
end

return {
  "sindrets/diffview.nvim",
  opts = {
    keymaps = {
      view = {
        { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Diffviewを閉じる" } },
      },
      file_panel = {
        { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Diffviewを閉じる" } },
        {
          "n",
          "j",
          function()
            jump_file_entry(1)
          end,
          { desc = "次のファイルへ移動して差分を表示(末尾で停止)" },
        },
        {
          "n",
          "k",
          function()
            jump_file_entry(-1)
          end,
          { desc = "前のファイルへ移動して差分を表示(先頭で停止)" },
        },
      },
      file_history_panel = {
        { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Diffviewを閉じる" } },
      },
    },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
    },
  },
}
