local M = {}

local function get_response_content(response)
  if type(response) == "string" then
    return response
  end

  if type(response) ~= "table" then
    return ""
  end

  if type(response.content) == "string" then
    return response.content
  end

  if type(response.message) == "string" then
    return response.message
  end

  if type(response.message) == "table" and type(response.message.content) == "string" then
    return response.message.content
  end

  return ""
end

local function clean_commit_message(response)
  local msg = vim.trim(get_response_content(response))

  -- コードブロックが含まれていた場合は除去する
  msg = msg:gsub("^```+[^\n]*\n?", ""):gsub("\n?```+%s*$", "")
  msg = vim.trim(msg)

  return vim.split(msg, "\n", { plain = true, trimempty = true })[1] or ""
end

function M.setup()
  local aug = vim.api.nvim_create_augroup("user.copilotchat", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    group = aug,
    callback = function(args)
      if vim.b[args.buf].__user_copilotchat_commit_prompted then
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

      vim.b[args.buf].__user_copilotchat_commit_prompted = true

      vim.defer_fn(function()
        local ok, chat = pcall(require, "CopilotChat")
        if not ok then
          return
        end

        chat.ask(
          "以下のステージ済み差分からConventional Commits形式（feat: ..., fix: ...等）で、日本語のコミットメッセージを1行だけ生成してください。出力はコミットメッセージ本文のみ（1行）にし、前置き・解説・コードブロックは出力しないでください。\n\n```diff\n"
            .. staged
            .. "\n```",
          {
            headless = true,
            system_prompt = "あなたはエンジニアです。与えられた差分から Conventional Commits 形式（feat: ..., fix: ...等）で、日本語のコミットメッセージを1つだけ生成してください。出力はコミットメッセージ本文のみ（1行）にし、前置き・解説・コードブロックは出力しないでください。",
            callback = function(response)
              vim.schedule(function()
                if not (args.buf and vim.api.nvim_buf_is_valid(args.buf)) then
                  return
                end

                local msg = clean_commit_message(response)
                if msg ~= "" then
                  vim.api.nvim_buf_set_lines(args.buf, 0, 0, false, { msg })
                end
              end)
            end,
          }
        )
      end, 100)
    end,
  })
end

return M
