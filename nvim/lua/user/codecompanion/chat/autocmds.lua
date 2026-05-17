local M = {}

function M.setup()
  local aug = vim.api.nvim_create_augroup("user.codecompanion", { clear = true })

  local function normalize_commit_message_layout(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
      return false
    end
    if vim.bo[bufnr].filetype ~= "gitcommit" then
      return false
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local first_nonblank, first_comment
    for i, line in ipairs(lines) do
      if not first_nonblank and line:match("%S") then
        first_nonblank = i
      end
      if not first_comment and line:match("^#") then
        first_comment = i
      end
      if first_nonblank and first_comment then
        break
      end
    end

    -- まだ件名がない、または件名より先にコメントが来る（LLM出力待ち）なら再試行
    if not first_nonblank or (first_comment and first_comment <= first_nonblank) then
      return false
    end

    if not first_comment then
      return true
    end

    local normalized = { lines[first_nonblank], "" }

    for i = first_comment, #lines do
      local prev = lines[i - 1]
      local cur = lines[i]
      local nxt = lines[i + 1]
      if not (cur == "" and prev and prev:match("^#") and nxt and nxt:match("^#")) then
        normalized[#normalized + 1] = cur
      end
    end

    if not vim.deep_equal(lines, normalized) then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, normalized)
    end

    return true
  end

  local function finalize_commit_layout_with_retry(bufnr, retries_left)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
      return
    end
    if not vim.b[bufnr].__user_codecompanion_commit_prompt_active then
      return
    end

    if normalize_commit_message_layout(bufnr) then
      vim.b[bufnr].__user_codecompanion_commit_prompt_active = nil
      return
    end

    if retries_left <= 0 then
      vim.b[bufnr].__user_codecompanion_commit_prompt_active = nil
      return
    end

    vim.defer_fn(function()
      finalize_commit_layout_with_retry(bufnr, retries_left - 1)
    end, 80)
  end

  require("user.codecompanion.highlights").setup()
  require("user.codecompanion.pending_edits").setup()

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatCreated",
    group = aug,
    callback = function(args)
      local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
      if not chat then
        return
      end

      require("user.codecompanion.chat.context").ensure_current_file_context(chat)
      vim.schedule(function()
        require("user.codecompanion.chat.context").set_chat_root_cwd(chat)
      end)

      require("user.codecompanion.chat.ui").setup_generating_indicator(chat)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    group = aug,
    callback = function(args)
      if vim.b[args.buf].__user_codecompanion_commit_prompted then
        return
      end

      local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:match("%S") and not line:match("^#") then
          return
        end
      end

      local staged = vim.system({ "git", "diff", "--no-ext-diff", "--staged" }, { text = true }):wait().stdout or ""
      if vim.trim(staged) == "" then
        return
      end

      vim.b[args.buf].__user_codecompanion_commit_prompted = true
      vim.b[args.buf].__user_codecompanion_commit_prompt_active = true

      vim.defer_fn(function()
        local ok, cc = pcall(require, "codecompanion")
        if ok then
          local approvals_ok, approvals = pcall(require, "codecompanion.interactions.chat.tools.approvals")
          if approvals_ok then
            approvals:always(args.buf, { tool_name = "inline" })
          end
          local prompt_ok, err = pcall(cc.prompt, "commit_ja")
          if not prompt_ok then
            vim.notify("CodeCompanion commit prompt failed: " .. tostring(err), vim.log.levels.WARN)
            vim.b[args.buf].__user_codecompanion_commit_prompt_active = nil
          end
        else
          vim.b[args.buf].__user_codecompanion_commit_prompt_active = nil
        end
      end, 100)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionInlineFinished",
    group = aug,
    callback = function()
      -- InlineFinished is emitted before inline output is placed in-buffer.
      -- Defer normalization so it runs after CodeCompanion writes the message.
      vim.defer_fn(function()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].__user_codecompanion_commit_prompt_active then
            finalize_commit_layout_with_retry(bufnr, 8)
          end
        end
      end, 120)
    end,
  })
end

return M
