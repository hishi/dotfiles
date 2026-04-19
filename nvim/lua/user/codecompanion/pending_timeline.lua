local M = {}

local api = vim.api

local NS = api.nvim_create_namespace("user.codecompanion.pending_timeline")

local function fmt_time(ts)
  if not ts then
    return "unknown-time"
  end
  return os.date("%Y-%m-%d %H:%M:%S", ts)
end

local function one_line(s)
  s = tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function split_lines(s)
  return vim.split(s or "", "\n", { plain = true })
end

local function diff_stats(original, proposed)
  local hunks = vim.diff(original or "", proposed or "", { result_type = "indices" }) or {}
  local added = 0
  local removed = 0
  for _, h in ipairs(hunks) do
    removed = removed + (h[2] or 0)
    added = added + (h[4] or 0)
  end
  return added, removed
end

local function current_entry_for_row(bufnr, entry_spans)
  local row0 = api.nvim_win_get_cursor(0)[1] - 1
  local selected = nil
  for _, span in ipairs(entry_spans) do
    if row0 >= span.start_row0 and row0 <= span.end_row0 then
      selected = span
      break
    end
  end
  return selected
end

---@param entry table
---@return string[] lines, string[] hls
local function build_entry_lines(entry)
  local original = entry.original or ""
  local proposed = entry.proposed or ""
  local old_lines = split_lines(original)
  local new_lines = split_lines(proposed)

  local hunks = vim.diff(original, proposed, { result_type = "indices" }) or {}

  local out_lines = {}
  local out_hls = {}

  local function push_line(text, hl)
    table.insert(out_lines, text)
    table.insert(out_hls, hl or "")
  end

  if #hunks == 0 then
    push_line("(no changes)", "Comment")
    return out_lines, out_hls
  end

  for _, h in ipairs(hunks) do
    local a_start, a_count, b_start, b_count = h[1], h[2], h[3], h[4]
    local paired = math.min(a_count, b_count)

    push_line(("@@ -%d,%d +%d,%d @@"):format(a_start, a_count, b_start, b_count), "Comment")

    -- Proposed first (new), then original (old) for each changed line.
    for i = 0, paired - 1 do
      local new_line = new_lines[b_start + i] or ""
      local old_line = old_lines[a_start + i] or ""
      push_line(new_line, "CodeCompanionDiffAdd")
      push_line(old_line, "CodeCompanionDiffDelete")
    end

    -- Extra additions
    if b_count > paired then
      for i = paired, b_count - 1 do
        local new_line = new_lines[b_start + i] or ""
        push_line(new_line, "CodeCompanionDiffAdd")
      end
    end

    -- Extra deletions
    if a_count > paired then
      for i = paired, a_count - 1 do
        local old_line = old_lines[a_start + i] or ""
        push_line(old_line, "CodeCompanionDiffDelete")
      end
    end

    push_line("", "")
  end

  return out_lines, out_hls
end

---@param opts? { filepath?: string, bufnr?: number }
function M.open(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or api.nvim_get_current_buf()
  local filepath = opts.filepath or api.nvim_buf_get_name(bufnr)
  if not filepath or filepath == "" then
    return vim.notify("CodeCompanion: no file for pending timeline", vim.log.levels.WARN)
  end

  local pe = require("user.codecompanion.pending_edits")
  local state = pe.get(filepath)
  local entries = state and state.entries or {}
  if #entries == 0 then
    return vim.notify("CodeCompanion: pending edits not found", vim.log.levels.INFO)
  end

  local display_path = vim.fn.fnamemodify(filepath, ":.")

  local timeline_buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = timeline_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = timeline_buf })
  api.nvim_set_option_value("swapfile", false, { buf = timeline_buf })
  api.nvim_set_option_value("modifiable", true, { buf = timeline_buf })
  api.nvim_set_option_value("filetype", "codecompanion", { buf = timeline_buf })

  local lines = {}
  local line_hls = {}
  local entry_spans = {}

  local function add(text, hl)
    table.insert(lines, text)
    table.insert(line_hls, hl or "")
  end

  add(("Pending timeline: %s"):format(display_path), "Title")
  add("q Close | <CR>/gv Diff view | gr Reject to here | ga Accept all | za Toggle fold", "Comment")
  add("", "")

  -- Newest first
  for i = #entries, 1, -1 do
    local e = entries[i]
    local added, removed = diff_stats(e.original, e.proposed)
    local explain = one_line(e.explanation)
    if explain ~= "" then
      explain = " — " .. explain
    end

    local start_row0 = #lines
    add(("Pending #%d  %s  +%d -%d%s  {{{"):format(i, fmt_time(e.saved_at), added, removed, explain), "FloatTitle")

    local entry_lines, entry_hls = build_entry_lines(e)
    for j = 1, #entry_lines do
      add(entry_lines[j], entry_hls[j])
    end

    add("}}}", "FloatTitle")
    add("", "")
    local end_row0 = #lines - 1

    table.insert(entry_spans, { start_row0 = start_row0, end_row0 = end_row0, entry = e, index = i })
  end

  api.nvim_buf_set_lines(timeline_buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = timeline_buf })

  api.nvim_buf_clear_namespace(timeline_buf, NS, 0, -1)
  for row0, hl in ipairs(line_hls) do
    if hl and hl ~= "" then
      pcall(api.nvim_buf_set_extmark, timeline_buf, NS, row0 - 1, 0, {
        line_hl_group = hl,
        priority = 200,
      })
    end
  end

  local width = math.min(math.max(90, math.floor(vim.o.columns * 0.75)), vim.o.columns - 4)
  local height = math.min(math.max(25, math.floor(vim.o.lines * 0.75)), vim.o.lines - 6)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  local win = api.nvim_open_win(timeline_buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.max(row, 0),
    col = math.max(col, 0),
    title = " CodeCompanion Pending Timeline ",
    title_pos = "center",
  })

  -- Folding is window-local.
  pcall(api.nvim_set_option_value, "foldmethod", "marker", { win = win })
  pcall(api.nvim_set_option_value, "foldmarker", "{{{,}}}", { win = win })
  pcall(api.nvim_set_option_value, "foldlevel", 1, { win = win })

  vim.keymap.set("n", "q", function()
    pcall(api.nvim_win_close, win, true)
  end, { buffer = timeline_buf, desc = "Close", nowait = true, silent = true })

  vim.keymap.set("n", "<cr>", function()
    local span = current_entry_for_row(timeline_buf, entry_spans)
    if not span or not span.entry then
      return
    end
    require("user.codecompanion.tools.insert_edit_into_file").show_pending_diff(span.entry, {
      title = ("%s (pending #%d)"):format(display_path, span.index),
      ft = span.entry.ft,
      filepath = filepath,
      index = span.index,
    })
  end, { buffer = timeline_buf, desc = "Open diff view", nowait = true, silent = true })

  vim.keymap.set("n", "gv", function()
    vim.cmd.normal({ args = { "<cr>" }, bang = true })
  end, { buffer = timeline_buf, desc = "Open diff view", nowait = true, silent = true })

  vim.keymap.set("n", "ga", function()
    local ok, err = require("user.codecompanion.pending_actions").accept_all(filepath)
    if ok then
      vim.notify(("CodeCompanion: accepted all pending for %s"):format(display_path), vim.log.levels.INFO)
    else
      vim.notify(("CodeCompanion: accept failed: %s"):format(err or "unknown"), vim.log.levels.ERROR)
    end
  end, { buffer = timeline_buf, desc = "Accept all pending", nowait = true, silent = true })

  vim.keymap.set("n", "gr", function()
    local span = current_entry_for_row(timeline_buf, entry_spans)
    if not span or not span.entry or not span.index then
      return
    end
    local ok, err = require("user.codecompanion.pending_actions").reject_to(filepath, span.index)
    if ok then
      vim.notify(
        ("CodeCompanion: rejected pending #%d and newer for %s"):format(span.index, display_path),
        vim.log.levels.WARN
      )
    else
      vim.notify(("CodeCompanion: reject failed: %s"):format(err or "unknown"), vim.log.levels.ERROR)
    end
  end, { buffer = timeline_buf, desc = "Reject to here", nowait = true, silent = true })
end

return M
