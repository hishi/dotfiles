local DEFAULT_GITGRAPH_ARGS = { all = true, max_count = 5000 }

local gitgraph_buf = nil

local function merge_gitgraph_args(args)
  return vim.tbl_deep_extend("force", DEFAULT_GITGRAPH_ARGS, args or {})
end

local function ensure_gitgraph_buffer()
  if gitgraph_buf and vim.api.nvim_buf_is_valid(gitgraph_buf) then
    return gitgraph_buf
  end

  gitgraph_buf = vim.api.nvim_create_buf(false, true)
  return gitgraph_buf
end

local function build_oneline_view(graph, lines, highlights)
  local oneline_lines = {}
  local oneline_highlights = {}
  local row_commits = {}
  local row_map = {}
  local line_prefix_lens = {}

  for idx = 1, #graph, 2 do
    local row = graph[idx]
    local commit = row and row.commit

    if commit then
      local new_row = #oneline_lines + 1
      local line_prefix = (lines[idx] or ""):gsub("%s*$", "")
      local message = commit.msg or ""

      row_map[idx] = new_row
      row_commits[new_row] = commit
      line_prefix_lens[new_row] = #line_prefix

      if message ~= "" then
        oneline_lines[new_row] = line_prefix .. "  " .. message
      else
        oneline_lines[new_row] = line_prefix
      end
    end
  end

  for _, hl in ipairs(highlights or {}) do
    local new_row = row_map[hl.row]
    if new_row then
      oneline_highlights[#oneline_highlights + 1] = {
        hg = hl.hg,
        row = new_row,
        start = hl.start,
        stop = hl.stop,
      }
    end
  end

  local message_hl = require("gitgraph.highlights").ITEM_HGS.message.name
  for row, commit in ipairs(row_commits) do
    if commit.msg and commit.msg ~= "" then
      local start_col = line_prefix_lens[row] + 2
      oneline_highlights[#oneline_highlights + 1] = {
        hg = message_hl,
        row = row,
        start = start_col,
        stop = start_col + #commit.msg,
      }
    end
  end

  local head_row = 1
  local head_found = false
  for row, commit in ipairs(row_commits) do
    for _, branch_name in ipairs(commit.branch_names or {}) do
      if branch_name:match("HEAD %->") then
        head_row = row
        head_found = true
        break
      end
    end
    if head_found then
      break
    end
  end

  return oneline_lines, oneline_highlights, row_commits, head_row
end

local function apply_oneline_mappings(buf, row_commits, hooks)
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local commit = row_commits[row]
    if commit then
      hooks.on_select_commit(commit)
    end
  end, { buffer = buf, desc = "select commit under cursor" })

  vim.keymap.set("v", "<CR>", function()
    vim.cmd('noau normal! "vy"')

    local start_row = vim.fn.getpos("'<")[2]
    local end_row = vim.fn.getpos("'>")[2]

    local to_commit = row_commits[start_row]
    local from_commit = row_commits[end_row]

    if from_commit and to_commit then
      hooks.on_select_range_commit(from_commit, to_commit)
    end
  end, { buffer = buf, desc = "select range of commit" })

  vim.keymap.set("n", "u", "<cmd>DiffviewOpen<cr>", {
    buffer = buf,
    silent = true,
    desc = "未コミット差分を開く (working tree vs index)",
  })

  vim.keymap.set("n", "U", "<cmd>DiffviewOpen --cached<cr>", {
    buffer = buf,
    silent = true,
    desc = "ステージ済み差分を開く (index vs HEAD)",
  })
end

local function draw_gitgraph_oneline(args)
  local log = require("gitgraph.log")
  local core = require("gitgraph.core")
  local gg = require("gitgraph")
  local utils = require("gitgraph.utils")

  if utils.check_cmd("git --version") then
    log.error("git command not found, please install it")
    return
  end

  if utils.check_cmd("git status") then
    log.error("does not seem to be a valid git repo")
    return
  end

  local graph, lines, highlights = core.gitgraph(gg.config, {}, merge_gitgraph_args(args))
  local oneline_lines, oneline_highlights, row_commits, head_row =
    build_oneline_view(graph, lines, highlights)

  local buf = ensure_gitgraph_buffer()
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, oneline_lines)
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  for _, hl in ipairs(oneline_highlights) do
    vim.api.nvim_buf_add_highlight(buf, -1, hl.hg, hl.row - 1, hl.start, hl.stop)
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  utils.apply_buffer_options(buf)
  apply_oneline_mappings(buf, row_commits, gg.config.hooks)

  if #oneline_lines > 0 then
    vim.api.nvim_win_set_cursor(0, { math.max(head_row, 1), 0 })
  end
end

local function draw_gitgraph_float()
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2 - 1)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
    relative = "editor",
    row = math.max(row, 0),
    col = math.max(col, 0),
    width = math.max(width, 60),
    height = math.max(height, 12),
    style = "minimal",
    border = "rounded",
  })

  draw_gitgraph_oneline()

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = 0, silent = true, desc = "GitGraph Floatを閉じる" })
end

return {
  "isakbm/gitgraph.nvim",
  opts = {
    git_cmd = "git",
    symbols = {
      merge_commit = "M",
      commit = "*",
    },
    format = {
      timestamp = "%H:%M:%S %d-%m-%Y",
      fields = { "hash", "timestamp", "author", "branch_name", "tag" },
    },
    hooks = {
      -- Check diff of a commit
      on_select_commit = function(commit)
        vim.notify("DiffviewOpen " .. commit.hash .. "^!")
        vim.cmd(":DiffviewOpen " .. commit.hash .. "^!")
      end,
      -- Check diff from commit a -> commit b
      on_select_range_commit = function(from, to)
        vim.notify("DiffviewOpen " .. from.hash .. "~1.." .. to.hash)
        vim.cmd(":DiffviewOpen " .. from.hash .. "~1.." .. to.hash)
      end,
    },
    -- hooks = {
    --   on_select_commit = function(commit)
    --     print("selected commit:", commit.hash)
    --   end,
    --   on_select_range_commit = function(from, to)
    --     print("selected range:", from.hash, to.hash)
    --   end,
    -- },
  },
  keys = {
    {
      "<leader>gl",
      function()
        draw_gitgraph_float()
      end,
      desc = "GitGraph - Draw (Float)",
    },
    {
      "<leader>gL",
      function()
        draw_gitgraph_oneline()
      end,
      desc = "GitGraph - Draw One Line (Current Window)",
    },
  },
}
