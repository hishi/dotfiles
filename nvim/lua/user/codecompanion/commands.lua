local M = {}

function M.setup()
  vim.cmd([[cab cc CodeCompanion]])

  vim.api.nvim_create_user_command("CodeCompanionCopilotStats", function()
    local ok_stats, stats = pcall(require, "codecompanion.adapters.http.copilot.stats")
    if not ok_stats or not stats or not stats.show then
      return vim.notify("Copilot stats are not available", vim.log.levels.WARN)
    end
    return stats.show()
  end, { desc = "Show Copilot usage/quota statistics" })

  vim.keymap.set("n", "<leader>ccs", "<cmd>CodeCompanionCopilotStats<cr>", { desc = "Copilot Stats" })
end

return M
