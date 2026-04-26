local M = {}

local function fmt_time(ts)
  if not ts then
    return "unknown-time"
  end
  return os.date("%Y-%m-%d %H:%M:%S", ts)
end

local function one_line(s)
  return tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
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

local function should_show_history_entry(entry)
  local reason = one_line(entry and entry.archived_reason)
  if reason == "accepted" or reason == "rejected" then
    return false
  end
  return true
end

local function same_session(entry, session_id)
  if not session_id then
    return entry and entry.session_id == nil
  end
  return entry and entry.session_id == session_id
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

    for i = 0, paired - 1 do
      local new_line = new_lines[b_start + i] or ""
      local old_line = old_lines[a_start + i] or ""
      push_line(new_line, "CodeCompanionDiffAdd")
      push_line(old_line, "CodeCompanionDiffDelete")
    end

    if b_count > paired then
      for i = paired, b_count - 1 do
        push_line(new_lines[b_start + i] or "", "CodeCompanionDiffAdd")
      end
    end

    if a_count > paired then
      for i = paired, a_count - 1 do
        push_line(old_lines[a_start + i] or "", "CodeCompanionDiffDelete")
      end
    end

    push_line("", "")
  end

  return out_lines, out_hls
end

---@param pending_entry table
---@param history_entries table[]
---@return table[]
function M.filter_history_entries(pending_entry, history_entries)
  local visible = {}
  local session_id = pending_entry and pending_entry.session_id
  for _, entry in ipairs(history_entries or {}) do
    if same_session(entry, session_id) and should_show_history_entry(entry) then
      table.insert(visible, entry)
    end
  end
  return visible
end

---@param filepath string
---@param pending_entry table
---@param visible_history_entries table[]
---@return { display_path: string, lines: string[], line_hls: string[], entry_spans: table[] }
function M.build(filepath, pending_entry, visible_history_entries)
  local display_path = vim.fn.fnamemodify(filepath, ":.")
  local lines = {}
  local line_hls = {}
  local entry_spans = {}

  local function add(text, hl)
    table.insert(lines, text)
    table.insert(line_hls, hl or "")
  end

  local function add_entry(label, label_hl, entry, title_for_diff)
    local added, removed = diff_stats(entry.original, entry.proposed)
    local explain = one_line(entry.explanation)
    if explain ~= "" then
      explain = " — " .. explain
    end
    local start_row0 = #lines
    add(("%s  %s  +%d -%d%s  {{{"):format(label, fmt_time(entry.saved_at or entry.archived_at), added, removed, explain), label_hl)
    local entry_lines, entry_hls = build_entry_lines(entry)
    for i = 1, #entry_lines do
      add(entry_lines[i], entry_hls[i])
    end
    add("}}}", label_hl)
    add("", "")
    table.insert(entry_spans, {
      start_row0 = start_row0,
      end_row0 = #lines - 1,
      entry = entry,
      title = title_for_diff,
    })
  end

  add(("Proposal history: %s"):format(display_path), "Title")
  add("q Close | <CR> Open Diff | Read-only", "Comment")
  add("", "")

  add_entry("Current Proposal", "FloatTitle", pending_entry, ("%s (current proposal)"):format(display_path))

  for i = #visible_history_entries, 1, -1 do
    local entry = visible_history_entries[i]
    local reason = one_line(entry.archived_reason)
    local label = ("Proposal History #%d"):format(i)
    if reason ~= "" then
      label = ("%s [%s]"):format(label, reason)
    end
    add_entry(label, "Comment", entry, ("%s (proposal history #%d)"):format(display_path, i))
  end

  return {
    display_path = display_path,
    lines = lines,
    line_hls = line_hls,
    entry_spans = entry_spans,
  }
end

return M
