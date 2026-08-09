local M = {}

local max_diff_chars = 1200
local context_begin = "# Copilot context: begin"
local context_end = "# Copilot context: end"
local suggestion_seed = "commit:"
local seed_var = "user_gitcommit_copilot_seed"
local seed_pattern = "^" .. vim.pesc(suggestion_seed) .. "%s*"
local allowed_types = {
  chore = true,
  docs = true,
  feat = true,
  fix = true,
  perf = true,
  refactor = true,
  style = true,
  test = true,
}

local function message_line(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for idx, line in ipairs(lines) do
    if line:match("%S") and not line:match("^#") then
      return idx - 1, line
    end
  end
end

local function buffer_has_message(buf)
  return message_line(buf) ~= nil
end

local function has_seed(buf)
  return vim.b[buf][seed_var] == true
end

local function seed_line_state(buf)
  if not has_seed(buf) then
    return nil
  end

  local _, line = message_line(buf)
  if line == suggestion_seed then
    return "seed"
  end

end

local function type_prefix_state(buf)
  local _, line = message_line(buf)
  local commit_type, summary = (line or ""):match("^(%w+):%s*(.*)$")
  if not allowed_types[commit_type] then
    return nil
  end
  return summary == "" and "prefix" or "completed"
end

local function truncate_text(text, max_chars)
  if vim.fn.strchars(text) <= max_chars then
    return text
  end

  return vim.fn.strcharpart(text, 0, max_chars) .. "\n... (truncated)"
end

local function comment_block(text)
  local lines = vim.split(vim.trim(text or ""), "\n", { plain = true })
  return "# " .. table.concat(lines, "\n# ")
end

local function staged_context()
  local name_status_result = vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--name-status" }, { text = true }):wait()
  local name_status = vim.trim(name_status_result.stdout or "")
  if name_status_result.code ~= 0 or name_status == "" then
    return nil
  end

  local stat_result = vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--stat" }, { text = true }):wait()
  local diff_result = vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--unified=0" }, { text = true }):wait()

  local context = table.concat({
    context_begin,
    "# Copilot: Generate a concise commit message for the staged changes below.",
    "# Copilot: Use Conventional Commits. Keep the subject on one line.",
    '# Copilot: Continue after the leading "commit:" seed with a type like " feat:" or " fix:".',
    "# Copilot: Keep the summary after the colon in Japanese.",
    "#",
    "# Staged files:",
    comment_block(name_status),
    "#",
    "# Change summary:",
    comment_block(stat_result.stdout),
    "#",
    "# Compact diff:",
    comment_block(truncate_text(diff_result.stdout, max_diff_chars)),
    context_end,
  }, "\n")

  return context
end

local function strip_seed_prefix(buf, only_completed)
  if not vim.api.nvim_buf_is_valid(buf) or not has_seed(buf) then
    return false
  end

  local row, line = message_line(buf)
  if not row or type(line) ~= "string" or line:sub(1, #suggestion_seed) ~= suggestion_seed then
    return false
  end

  local replacement = line:gsub(seed_pattern, "", 1)
  if only_completed then
    local commit_type, summary = replacement:match("^(%w+):%s*(.*)$")
    if not allowed_types[commit_type] or summary == "" then
      return false
    end
  end

  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { replacement })
  vim.b[buf][seed_var] = false

  local cursor = vim.api.nvim_win_get_cursor(0)
  if cursor[1] == row + 1 then
    local removed_chars = vim.fn.strchars(line) - vim.fn.strchars(replacement)
    pcall(vim.api.nvim_win_set_cursor, 0, { cursor[1], math.max(0, cursor[2] - removed_chars) })
  end

  return true
end

local function remove_copilot_context(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  strip_seed_prefix(buf, true)

  if type_prefix_state(buf) ~= "completed" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local start_idx
  local end_idx

  for idx, line in ipairs(lines) do
    if line == context_begin then
      start_idx = idx
    elseif start_idx and line == context_end then
      end_idx = idx
      break
    end
  end

  if not start_idx or not end_idx then
    return
  end

  if lines[end_idx + 1] == "" then
    end_idx = end_idx + 1
  end

  vim.api.nvim_buf_set_lines(buf, start_idx - 1, end_idx, false, {})

  local row = message_line(buf)
  if row then
    local message = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, #message })
  end
end

local function insert_template(buf)
  if buffer_has_message(buf) then
    return
  end

  local context = staged_context()
  if not context then
    return
  end

  vim.b[buf][seed_var] = true

  local lines = vim.split(suggestion_seed .. "\n" .. context, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, #suggestion_seed })

  vim.schedule(function()
    if vim.api.nvim_get_current_buf() == buf and #vim.api.nvim_list_uis() > 0 then
      vim.cmd("startinsert!")
      for _, delay in ipairs({ 500, 1500, 3000 }) do
        vim.defer_fn(function()
          if vim.api.nvim_get_current_buf() == buf and vim.fn.mode():match("^[iR]") and seed_line_state(buf) == "seed" then
            pcall(vim.fn["copilot#Suggest"])
          end
        end, delay)
      end
    end
  end)
end

function M.setup()
  local aug = vim.api.nvim_create_augroup("user.gitcommit.copilot", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    group = aug,
    callback = function(args)
      vim.bo[args.buf].swapfile = false
      insert_template(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "TextChangedI" }, {
    pattern = "COMMIT_EDITMSG",
    group = aug,
    callback = function(args)
      remove_copilot_context(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "COMMIT_EDITMSG",
    group = aug,
    callback = function(args)
      if seed_line_state(args.buf) == "seed" then
        strip_seed_prefix(args.buf, false)
      end
    end,
  })
end

function M.cleanup_after_accept(buf)
  strip_seed_prefix(buf or vim.api.nvim_get_current_buf(), true)
  remove_copilot_context(buf or vim.api.nvim_get_current_buf())
end

return M
