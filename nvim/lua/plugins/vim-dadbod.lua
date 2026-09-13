return {
  "kristijanhusak/vim-dadbod-ui",
  init = function()
    vim.g.db_ui_use_nerd_fonts = 1
    vim.g.db_ui_win_position = "left"
    vim.g.db_ui_winwidth = 40
    vim.g.db_ui_show_database_icon = 1
    vim.g.db_ui_use_nvim_notify = 1

    vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui_queries"
    vim.g.db_ui_tmp_query_location = vim.fn.stdpath("data") .. "/db_ui_queries/tmp"
    vim.g.db_ui_table_helpers = {
      mysql = {
        Count = "select count(*) from {optional_schema}{table}",
        Describe = "describe {optional_schema}{table}",
      },
    }
    vim.g.db_ui_auto_execute_table_helpers = 1
    -- 保存時に自動再実行する(巨大なクエリを保存する場合はクラッシュしうる点に注意)
    vim.g.db_ui_execute_on_save = true

    local ok, secrets = pcall(require, "config.secrets")
    vim.g.dbs = ok and secrets.dbs or {}
  end,
}
