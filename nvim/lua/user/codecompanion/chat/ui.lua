local M = {}

function M.setup_generating_indicator(chat)
  local ns_generating = vim.api.nvim_create_namespace("codecompanion-generating")
  local generating_mark = nil
  local generating_seq = 0

  local function clear_generating()
    generating_seq = generating_seq + 1
    if generating_mark then
      pcall(vim.api.nvim_buf_del_extmark, chat.bufnr, ns_generating, generating_mark)
      generating_mark = nil
    end
  end

  chat:add_callback("on_submitted", function()
    clear_generating()
    local my_seq = generating_seq + 1
    generating_seq = my_seq

    local function render_at_bottom()
      if my_seq ~= generating_seq then
        return
      end
      if not vim.api.nvim_buf_is_valid(chat.bufnr) then
        return
      end

      local lc = vim.api.nvim_buf_line_count(chat.bufnr)
      local row = math.max(lc - 1, 0)
      generating_mark = vim.api.nvim_buf_set_extmark(chat.bufnr, ns_generating, row, 0, {
        id = generating_mark,
        strict = false,
        virt_lines = {
          { { "" } },
          { { " generating…", "Comment" } },
        },
        virt_lines_above = false,
        priority = 120,
      })
      vim.defer_fn(render_at_bottom, 120)
    end

    render_at_bottom()
  end)

  chat:add_callback("on_completed", clear_generating)
  chat:add_callback("on_cancelled", clear_generating)
  chat:add_callback("on_ready", clear_generating)
end

return M
