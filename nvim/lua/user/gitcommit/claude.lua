local M = {}

local prompt =
  "日本語のConventional Commitを1行だけ出力。コロン以降は必ず日本語。typeはfeat, fix, refactor, docs, test, chore, style, perfから選ぶ。説明不要。"

local claude_command = "/Users/hishi/.local/bin/claude"
local claude_model = "claude-haiku-4-5-20251001"
local log_file = vim.fn.stdpath("config") .. "/state/gitcommit-ai.log"
local max_diff_chars = 1000
local auto_cascade_delay_ms = 150
local session_rotate_after = 20
local session_ttl_ms = 4 * 60 * 1000

-- vim.b can only hold values convertible to VimL, so the vim.system() handle
-- (userdata) is tracked here instead, keyed by buffer number.
local pending_procs = {}

-- lazygit runs `nvim` as a fresh process per commit (git core.editor), so
-- there is no long-lived Neovim instance to hold session state in memory.
-- The session id is persisted to disk instead: a resumed `claude` session
-- reuses the cached system prompt (roughly 3-4x faster than a cold call).
-- `claude --resume` is tied to the directory a session was created in, so
-- sessions are kept one-per-repo (keyed by the repo root) rather than a
-- single global file; resuming a different project's session id fails
-- immediately (code=1) otherwise. `session_file_lock` only guards against
-- two commits racing within the same process (rare, but cheap to avoid).
local session_dir = vim.fn.stdpath("config") .. "/state/gitcommit-ai-sessions"
local session_file_lock = false

math.randomseed(os.time())

local function new_session_id()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (
    template:gsub("[xy]", function(c)
      local v = (c == "x") and math.random(0, 0xf) or math.random(0x8, 0xb)
      return string.format("%x", v)
    end)
  )
end

local function repo_session_file()
  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  local root = vim.trim(result.stdout or "")
  if result.code ~= 0 or root == "" then
    root = vim.fn.getcwd()
  end

  local key = root:gsub("[^%w]", "_")
  return session_dir .. "/" .. key .. ".json"
end

local function read_session_file(session_file)
  local ok, lines = pcall(vim.fn.readfile, session_file)
  if not ok or not lines or #lines == 0 then
    return nil
  end

  local decode_ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decode_ok or type(data) ~= "table" or not data.id then
    return nil
  end

  return data
end

local function write_session_file(session_file, data)
  vim.fn.mkdir(session_dir, "p")
  local ok, encoded = pcall(vim.json.encode, data)
  if ok then
    pcall(vim.fn.writefile, { encoded }, session_file)
  end
end

local function delete_session_file(session_file)
  pcall(vim.fn.delete, session_file)
end

-- Returns session_id, primed, session_data, session_file (nil id means "no
-- session, call standalone"). session_data/session_file must both be passed
-- back to release_session().
local function acquire_session()
  if session_file_lock then
    return nil
  end

  session_file_lock = true

  local session_file = repo_session_file()
  local data = read_session_file(session_file)
  local now = os.time() * 1000
  local primed = false

  if data and data.uses and data.updated_at then
    if (now - data.updated_at) <= session_ttl_ms and data.uses < session_rotate_after then
      primed = true
    else
      data = nil
    end
  else
    data = nil
  end

  if not data then
    data = { id = new_session_id(), uses = 0, updated_at = now }
  end

  return data.id, primed, data, session_file
end

local function release_session(data, session_file, success)
  session_file_lock = false

  if not data then
    return
  end

  if success then
    data.uses = data.uses + 1
    data.updated_at = os.time() * 1000
    write_session_file(session_file, data)
  else
    delete_session_file(session_file)
  end
end

local function now_ms()
  return vim.uv.hrtime() / 1000000
end

local function elapsed_ms(started_at)
  return math.floor(now_ms() - started_at + 0.5)
end

local function log(message)
  local line = string.format("%s %s\n", os.date("%Y-%m-%d %H:%M:%S"), message)

  local function write()
    local log_dir = vim.fn.fnamemodify(log_file, ":h")
    vim.fn.mkdir(log_dir, "p")
    local ok, err = pcall(vim.fn.writefile, { vim.trim(line) }, log_file, "a")
    if not ok then
      vim.notify("Failed to write gitcommit AI log: " .. tostring(err), vim.log.levels.WARN)
    end
  end

  if vim.in_fast_event() then
    vim.schedule(write)
  else
    write()
  end
end

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

local function replace_message_if_unchanged(buf, expected, msg)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local row, current = message_line(buf)
  if current == expected then
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { msg })
  elseif not current then
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { msg })
  end
end

local function staged_changes(name_status)
  local changes = {}

  for _, line in ipairs(vim.split(name_status or "", "\n", { plain = true, trimempty = true })) do
    local status, rest = line:match("^(%S+)%s+(.+)$")
    if status and rest then
      local path = rest:match("^[^\t]+\t(.+)$") or rest
      table.insert(changes, { status = status:sub(1, 1), path = path })
    end
  end

  return changes
end

local function has_path(paths, pattern)
  for _, path in ipairs(paths) do
    if path:match(pattern) then
      return true
    end
  end

  return false
end

local function commit_type(paths)
  local changes = paths.changes or {}
  local has_source = false
  local has_test = false
  local has_docs = false
  local has_added = false
  local has_deleted = false

  if has_path(paths, "gitcommit") or has_path(paths, "copilotchat") then
    return "refactor"
  end

  if has_path(paths, "terminal") then
    return "feat"
  end

  if has_path(paths, "lazy%-lock%.json") or has_path(paths, "plugins/") then
    return "chore"
  end

  for _, change in ipairs(changes) do
    has_added = has_added or change.status == "A"
    has_deleted = has_deleted or change.status == "D"
  end

  for _, path in ipairs(paths) do
    if path:match("%.md$") or path:match("README") or path:match("^docs/") then
      has_docs = true
    elseif path:match("[Tt]est") or path:match("spec") then
      has_test = true
    else
      has_source = true
    end
  end

  if has_test and not has_source then
    return "test"
  end

  if has_docs and not has_source then
    return "docs"
  end

  if has_added and not has_deleted then
    return "feat"
  end

  if has_deleted then
    return "refactor"
  end

  return "chore"
end

local function commit_scope(paths)
  if has_path(paths, "gitcommit") or has_path(paths, "copilotchat") then
    return "gitcommit"
  end

  if has_path(paths, "terminal") then
    return "terminal"
  end

  if has_path(paths, "keymaps") then
    return "keymaps"
  end

  if has_path(paths, "plugins") or has_path(paths, "lazy%-lock%.json") then
    return "plugins"
  end

  for _, path in ipairs(paths) do
    local scope = path:match("^nvim/lua/([^/]+)/")
      or path:match("^lua/([^/]+)/")
      or path:match("^nvim/([^/]+)/")
      or path:match("^([^/]+)/")

    if scope and scope ~= "" and not scope:match("^%.") then
      return scope:gsub("%.lua$", "")
    end
  end
end

local function fallback_summary(paths)
  if has_path(paths, "gitcommit") or has_path(paths, "copilotchat") then
    return "コミットメッセージ生成を更新"
  end

  if has_path(paths, "terminal") then
    return "ターミナル設定を更新"
  end

  if has_path(paths, "keymaps") then
    return "キーマップを更新"
  end

  if has_path(paths, "plugins") or has_path(paths, "lazy%-lock%.json") then
    return "プラグイン設定を更新"
  end

  if has_path(paths, "zshrc") then
    return "シェル設定を更新"
  end

  if has_path(paths, "nvim/") or has_path(paths, "lua/") then
    return "Neovim設定を更新"
  end

  return "変更内容を更新"
end

local function fallback_message(name_status)
  local changes = staged_changes(name_status)
  local paths = {}
  paths.changes = changes

  for _, change in ipairs(changes) do
    table.insert(paths, change.path)
  end

  local kind = commit_type(paths)
  local scope = commit_scope(paths)
  local summary = fallback_summary(paths)

  if scope then
    return string.format("%s(%s): %s", kind, scope, summary)
  end

  return kind .. ": " .. summary
end

local function clean_message(output)
  local msg = vim.trim(output or "")
  msg = msg:gsub("^```+[^\n]*\n?", ""):gsub("\n?```+%s*$", "")

  for _, line in ipairs(vim.split(msg, "\n", { plain = true, trimempty = true })) do
    line = vim.trim(line)
    if line ~= "" then
      return line
    end
  end

  return ""
end

local function has_japanese_summary(msg)
  local summary = msg:match(":%s*(.+)$") or msg
  return summary:match("[\128-\255]") ~= nil
end

local function insert_message(buf, msg)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if buffer_has_message(buf) then
    return false
  end

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { msg })
  return true
end

local function truncate_text(text, max_chars)
  if vim.fn.strchars(text) <= max_chars then
    return text, false
  end

  return vim.fn.strcharpart(text, 0, max_chars), true
end

-- Parses `git diff --unified=0` output into per-file {path, lines} chunks,
-- dropping the diff --git/index/---/+++ header boilerplate (the file path
-- is already shown separately in the Files: section, so repeating those 4
-- lines per file just eats into the per-file character budget below).
local function split_diff_by_file(diff_text)
  local files = {}
  local current

  local function flush()
    if current then
      table.insert(files, current)
    end
  end

  for _, line in ipairs(vim.split(diff_text, "\n", { plain = true })) do
    local path = line:match("^diff %-%-git a/.- b/(.*)$")
    if path then
      flush()
      current = { path = path, lines = {} }
    elseif current then
      if
        line:match("^@@")
        or (line:match("^[%+%-]") and not line:match("^%+%+%+ ") and not line:match("^%-%-%- "))
      then
        table.insert(current.lines, line)
      end
    end
  end
  flush()

  return files
end

-- Splits max_chars evenly across every changed file's diff instead of
-- truncating the whole concatenated diff, so a large early file (e.g. a
-- lockfile) can't consume the entire budget and leave later files with no
-- diff content at all.
local function truncate_diff_per_file(diff_text, max_chars)
  local files = split_diff_by_file(diff_text)
  if #files == 0 then
    return "", false
  end

  local per_file_budget = math.max(1, math.floor(max_chars / #files))
  local parts = {}
  local any_truncated = false

  for _, file in ipairs(files) do
    local header = "### " .. file.path
    local body = table.concat(file.lines, "\n")
    local budget = math.max(0, per_file_budget - #header - 1)
    local truncated_body, file_truncated = truncate_text(body, budget)
    if file_truncated then
      any_truncated = true
      truncated_body = truncated_body .. "\n... (truncated)"
    end
    table.insert(parts, header .. "\n" .. truncated_body)
  end

  return table.concat(parts, "\n\n"), any_truncated
end

local function prompt_with_diff(diff_context)
  return prompt .. "\n\n" .. diff_context
end

local function kill_pending_process(buf)
  local proc = pending_procs[buf]
  if proc then
    pending_procs[buf] = nil
    pcall(function()
      proc:kill(15)
    end)
  end
end

local function ensure_cleanup_autocmd(buf)
  if vim.b[buf].__user_claude_commit_cleanup_setup then
    return
  end

  vim.b[buf].__user_claude_commit_cleanup_setup = true
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = buf,
    once = true,
    callback = function()
      kill_pending_process(buf)
    end,
  })
end

local function generate_with_claude(buf, diff_context, fallback, total_started_at, on_done)
  if not vim.uv.fs_stat(claude_command) then
    log("claude cli missing")
    if on_done then
      on_done()
    end
    return
  end

  local args = { claude_command, "--model", claude_model, "--exclude-dynamic-system-prompt-sections" }
  local session_id, session_primed, session_data, session_file = acquire_session()
  if session_id then
    if session_primed then
      vim.list_extend(args, { "--resume", session_id })
    else
      vim.list_extend(args, { "--session-id", session_id })
    end
  end
  vim.list_extend(args, { "-p", prompt_with_diff(diff_context) })

  local started_at = now_ms()
  local proc
  proc = vim.system(args, { text = true }, function(result)
    log(
      "claude elapsed_ms="
        .. elapsed_ms(started_at)
        .. " code="
        .. result.code
        .. " session="
        .. (session_id and (session_primed and "resume" or "new") or "none")
    )

    vim.schedule(function()
      if pending_procs[buf] == proc then
        pending_procs[buf] = nil
      end

      if session_data then
        if result.code == 0 then
          release_session(session_data, session_file, true)
        else
          log("claude session call failed, resetting session")
          release_session(session_data, session_file, false)
        end
      end

      if result.code ~= 0 then
        log("claude failed code=" .. result.code)
        if on_done then
          on_done()
        end
        return
      end

      local msg = clean_message(result.stdout)
      log("commit message generated empty=" .. tostring(msg == ""))
      if msg ~= "" then
        if not has_japanese_summary(msg) then
          log("commit message ignored non_japanese=true")
          if on_done then
            on_done()
          end
          return
        end

        replace_message_if_unchanged(buf, fallback, msg)
        log("total elapsed_ms=" .. elapsed_ms(total_started_at))
      end

      if on_done then
        on_done()
      end
    end)
  end)

  pending_procs[buf] = proc
end

local function diff_context(max_chars, cached_name_status)
  local stat_started_at = now_ms()
  local stat_result = vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--stat" }, { text = true }):wait()
  log("git diff stat elapsed_ms=" .. elapsed_ms(stat_started_at) .. " code=" .. stat_result.code)

  local name_status
  if cached_name_status then
    name_status = vim.trim(cached_name_status)
  else
    local name_status_started_at = now_ms()
    local name_status_result =
      vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--name-status" }, { text = true }):wait()
    log(
      "git diff name-status elapsed_ms=" .. elapsed_ms(name_status_started_at) .. " code=" .. name_status_result.code
    )
    name_status = vim.trim(name_status_result.stdout or "")
  end

  local diff_started_at = now_ms()
  local diff_result = vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--unified=0" }, { text = true }):wait()
  log("git diff compact elapsed_ms=" .. elapsed_ms(diff_started_at) .. " code=" .. diff_result.code)

  local stat = vim.trim(stat_result.stdout or "")
  if name_status == "" then
    return nil, nil
  end

  local compact_diff, truncated = truncate_diff_per_file(diff_result.stdout or "", max_chars)
  log(
    "staged diff bytes="
      .. #(diff_result.stdout or "")
      .. " compact_bytes="
      .. #compact_diff
      .. " truncated="
      .. tostring(truncated)
  )

  local context = table.concat({
    "Files:",
    "```text",
    name_status,
    "```",
    "",
    "Stats:",
    "```text",
    stat,
    "```",
    "",
    truncated and ("Diff (truncated per file, up to " .. max_chars .. " chars total):") or "Diff:",
    "```diff",
    vim.trim(compact_diff),
    "```",
  }, "\n")

  return context, fallback_message(name_status), #(diff_result.stdout or "")
end

local function run_generation(buf, opts)
  opts = opts or {}

  if vim.b[buf].__user_claude_commit_running then
    log("skipped, already running")
    return
  end

  vim.b[buf].__user_claude_commit_running = true
  local total_started_at = now_ms()
  local context, fallback, diff_bytes = diff_context(max_diff_chars, opts.cached_name_status)

  if not context then
    vim.b[buf].__user_claude_commit_running = false
    return
  end

  log("claude requested diff_bytes=" .. diff_bytes)

  ensure_cleanup_autocmd(buf)
  local _, current = message_line(buf)
  generate_with_claude(buf, context, current or fallback, total_started_at, function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.b[buf].__user_claude_commit_running = false
    end
  end)
end

function M.setup()
  local aug = vim.api.nvim_create_augroup("user.gitcommit.claude", { clear = true })
  log("setup provider=claude log_file=" .. log_file)

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    group = aug,
    callback = function(args)
      if vim.b[args.buf].__user_claude_commit_prompted then
        return
      end

      if buffer_has_message(args.buf) then
        return
      end

      local total_started_at = now_ms()
      local name_status_started_at = now_ms()
      local name_status_result =
        vim.system({ "git", "diff", "--no-ext-diff", "--staged", "--name-status" }, { text = true }):wait()
      log("git diff name-status elapsed_ms=" .. elapsed_ms(name_status_started_at) .. " code=" .. name_status_result.code)

      if vim.trim(name_status_result.stdout or "") == "" then
        return
      end

      vim.b[args.buf].__user_claude_commit_prompted = true
      local fallback = fallback_message(name_status_result.stdout)
      local inserted_fallback = insert_message(args.buf, fallback)
      log("fallback inserted=" .. tostring(inserted_fallback) .. " message=" .. fallback)
      log("total elapsed_ms=" .. elapsed_ms(total_started_at))

      if inserted_fallback then
        local name_status_snapshot = name_status_result.stdout
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            run_generation(args.buf, { cached_name_status = name_status_snapshot })
          end
        end, auto_cascade_delay_ms)
      end
    end,
  })
end

return M
