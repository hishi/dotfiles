local Path = require("plenary.path")
local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")

local approvals = require("codecompanion.interactions.chat.tools.approvals")
local constants = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.constants")
local io_mod = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.io")
local json_repair = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.json_repair")
local match_selector = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.match_selector")
local process_mod = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.process")

local config = require("codecompanion.config")

local api = vim.api
local fmt = string.format

local NS = vim.api.nvim_create_namespace("user.codecompanion.inline_diff")
local HELP_HL = "UserCodeCompanionInlineHelp"
local PROPOSED_ADD_HL = "UserCodeCompanionProposedAdd"
local PROPOSED_CHANGE_HL = "UserCodeCompanionProposedChange"
local OLDLINE_HL = "UserCodeCompanionOldLine"

local function has_hl(name)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name })
  if not ok or not hl then
    return false
  end
  return (hl.fg ~= nil) or (hl.bg ~= nil) or (hl.sp ~= nil) or (hl.link ~= nil)
end

local function has_bg(name)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name })
  return ok and hl and (hl.bg ~= nil)
end

local function buf_win_width(bufnr)
  local win = (vim.fn.win_findbuf(bufnr) or {})[1]
  if win and api.nvim_win_is_valid(win) then
    return api.nvim_win_get_width(win)
  end
  return 80
end

local function pad_to_width(text, width)
  local w = vim.fn.strdisplaywidth(text)
  local pad = math.max(0, width - w)
  return text .. string.rep(" ", pad)
end

local function first_non_ws_col0(line)
  if not line or line == "" then
    return 0
  end
  local s = line:find("%S")
  if not s then
    return 0
  end
  return s - 1
end

local function ensure_proposed_hl()
  -- Mirror CodeCompanion diff view: additions/changes use CodeCompanionDiffAdd.
  -- Do not use `default=true` here: this needs to overwrite any previous user experiments
  -- so the inline buffer view always matches the diff view.
  pcall(api.nvim_set_hl, 0, PROPOSED_ADD_HL, { link = "CodeCompanionDiffAdd" })
  pcall(api.nvim_set_hl, 0, PROPOSED_CHANGE_HL, { link = "CodeCompanionDiffAdd" })
end

local function ensure_oldline_hl()
  -- Mirror CodeCompanion diff view: deletions use CodeCompanionDiffDelete.
  pcall(api.nvim_set_hl, 0, OLDLINE_HL, { link = "CodeCompanionDiffDelete" })
end

local function ensure_help_hl()
  local fg
  local bg
  -- User preference: high-visibility banner background.
  fg = "#0b1220"
  bg = "#F7FF89"
  pcall(api.nvim_set_hl, 0, HELP_HL, { fg = fg, bg = bg, bold = true, cterm = { bold = true } })
end

local function load_prompt()
  local source_path = debug.getinfo(1, "S").source:sub(2)
  local dir = vim.fn.fnamemodify(source_path, ":h")
  local prompt_path = Path:new(dir, "insert_edit_into_file_prompt.md")
  if prompt_path:exists() then
    return prompt_path:read()
  end

  -- Fallback to upstream prompt
  local upstream = debug.getinfo(process_mod.process_edits, "S")
  local upstream_dir = upstream and upstream.source and vim.fn.fnamemodify(upstream.source:sub(2), ":h") or nil
  if upstream_dir then
    local p = Path:new(upstream_dir, "prompt.md")
    if p:exists() then
      return p:read()
    end
  end

  return "Edit a file by applying deterministic text replacements."
end

local PROMPT = load_prompt()

local function make_response(status, msg)
  return { status = status, data = msg }
end

local function extract_explanation(action)
  local explanation = action.explanation or (action.edits and action.edits[1] and action.edits[1].explanation)
  return (explanation and explanation ~= "") and ("\n" .. explanation) or ""
end

local function split_lines(s)
  return vim.split(s, "\n", { plain = true })
end

local function set_buffer_content(bufnr, content)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = split_lines(content)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  pcall(api.nvim_set_option_value, "modified", false, { buf = bufnr })
end

local function clear_inline_visual(bufnr)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  pcall(api.nvim_buf_clear_namespace, bufnr, NS, 0, -1)

  pcall(vim.keymap.del, "n", "ga", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "gr", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "gv", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "gH", { buffer = bufnr })

  pcall(function()
    vim.b[bufnr].__user_codecompanion_inline_diff = nil
    vim.b[bufnr].__user_codecompanion_inline_diff_state = nil
  end)
end

local function accept_inline(bufnr)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  local st = vim.b[bufnr].__user_codecompanion_inline_diff_state
  local filepath = st and st.filepath or api.nvim_buf_get_name(bufnr)
  if filepath and filepath ~= "" then
    pcall(function()
      require("user.codecompanion.pending_edits").remove_all(filepath)
    end)
  end
  clear_inline_visual(bufnr)
end

local function reject_inline(bufnr, restore_fn)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return false, "Invalid buffer"
  end
  local st = vim.b[bufnr].__user_codecompanion_inline_diff_state
  local filepath = st and st.filepath or api.nvim_buf_get_name(bufnr)

  local ok, err = restore_fn()
  if not ok then
    return false, err
  end

  if filepath and filepath ~= "" then
    pcall(function()
      require("user.codecompanion.pending_edits").pop(filepath)
    end)
  end

  clear_inline_visual(bufnr)

  -- If there is an older pending edit for this file and the buffer matches it,
  -- rehydrate the inline diff so the user can resolve it next.
  if filepath and filepath ~= "" then
    pcall(function()
      require("user.codecompanion.pending_edits").try_restore_for_buf(bufnr)
    end)
  end

  return true, nil
end

local function apply_inline_diff(bufnr, original_content, new_content, restore_fn, show_diff_fn, persist, meta)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  clear_inline_visual(bufnr)
  ensure_proposed_hl()
  ensure_oldline_hl()

  local hunks = vim.diff(original_content, new_content, { result_type = "indices" }) or {}
  local old_lines = split_lines(original_content)

  local function clamp_row_0(row0)
    local lc = api.nvim_buf_line_count(bufnr)
    if lc <= 0 then
      return 0
    end
    return math.min(math.max(row0, 0), lc - 1)
  end

  local function line_indent_at(row0)
    row0 = clamp_row_0(row0)
    local line = (api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1]) or ""
    return line:match("^%s*") or ""
  end

  local function annotate_old_line(row0, old_line)
    old_line = old_line or ""
    row0 = clamp_row_0(row0)

    local width = buf_win_width(bufnr)
    local indent = old_line:match("^%s*") or ""
    local rest = old_line:sub(#indent + 1)
    local padded_rest = pad_to_width(rest, math.max(0, width - vim.fn.strdisplaywidth(indent)))
    api.nvim_buf_set_extmark(bufnr, NS, row0, 0, {
      virt_lines = {
        { { indent, OLDLINE_HL }, { padded_rest, OLDLINE_HL } },
      },
      virt_lines_above = false,
      priority = 115,
    })
  end

  local function set_help_banner_at(row0)
    ensure_help_hl()
    local msg = " CodeCompanion  ga Accept  gr Reject  gv Diff  gH Timeline "
    row0 = clamp_row_0(row0)
    local indent = line_indent_at(row0)
    api.nvim_buf_set_extmark(bufnr, NS, row0, 0, {
      virt_lines = {
        { { indent, "Normal" }, { msg, HELP_HL } },
      },
      virt_lines_above = row0 > 0,
      priority = 200,
    })
  end

  local first_change_row0 = nil
  for _, h in ipairs(hunks) do
    local a_start, a_count, b_start, b_count = h[1], h[2], h[3], h[4]
    local candidate_row0 = clamp_row_0((b_start - 1))
    if first_change_row0 == nil or candidate_row0 < first_change_row0 then
      first_change_row0 = candidate_row0
    end

    if b_count > 0 then
      local hl = (a_count == 0) and PROPOSED_ADD_HL or PROPOSED_CHANGE_HL
      for i = 0, b_count - 1 do
        local row0 = clamp_row_0((b_start - 1) + i)
        local line = (api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1]) or ""
        local col0 = first_non_ws_col0(line)
        -- Match CodeCompanion diff view: use a line highlight (reliably visible),
        -- but preserve indentation by masking the leading whitespace back to Normal.
        api.nvim_buf_set_extmark(bufnr, NS, row0, 0, {
          line_hl_group = hl,
          priority = 240,
        })
        if col0 > 0 then
          api.nvim_buf_set_extmark(bufnr, NS, row0, 0, {
            end_col = col0,
            hl_group = "Normal",
            hl_mode = "replace",
            priority = 260,
          })
        end
      end
    end

    if a_count > 0 then
      local paired = math.min(a_count, b_count)

      -- For changed lines, annotate the original line alongside the proposed one.
      if paired > 0 then
        for i = 0, paired - 1 do
          local old_line = old_lines[(a_start - 1) + 1 + i] or ""
          local row0 = clamp_row_0((b_start - 1) + i)
          annotate_old_line(row0, old_line)
        end
      end

      -- For deletions (extra old lines with no corresponding new line), keep showing
      -- them as virtual lines around the nearest anchor.
      if a_count > b_count then
        local deleted = {}
        local width = buf_win_width(bufnr)
        for i = paired, a_count - 1 do
          local l = old_lines[(a_start - 1) + 1 + i] or ""
          local indent = l:match("^%s*") or ""
          local rest = l:sub(#indent + 1)
          local padded_rest = pad_to_width(rest, math.max(0, width - vim.fn.strdisplaywidth(indent)))
          table.insert(deleted, { { indent, OLDLINE_HL }, { padded_rest, OLDLINE_HL } })
        end

        local anchor_row0 = clamp_row_0((b_start - 1) + paired)
        api.nvim_buf_set_extmark(bufnr, NS, anchor_row0, 0, {
          virt_lines = deleted,
          virt_lines_above = true,
          priority = 110,
        })
      end
    end
  end

  if first_change_row0 ~= nil then
    set_help_banner_at(first_change_row0)
  else
    set_help_banner_at(0)
  end

  vim.b[bufnr].__user_codecompanion_inline_diff = true
  meta = meta or {}
  vim.b[bufnr].__user_codecompanion_inline_diff_state = {
    filepath = api.nvim_buf_get_name(bufnr),
    original = original_content,
    proposed = new_content,
    ft = meta.ft or vim.bo[bufnr].filetype,
    title = meta.title or vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":."),
    explanation = meta.explanation,
    saved_at = os.time(),
  }
  if persist ~= false then
    pcall(function()
      local pe = require("user.codecompanion.pending_edits")
      local id = pe.push(vim.b[bufnr].__user_codecompanion_inline_diff_state)
      vim.b[bufnr].__user_codecompanion_inline_diff_state.id = id
      local filepath = vim.b[bufnr].__user_codecompanion_inline_diff_state.filepath
      local st = filepath and pe.get(filepath) or nil
      local count = st and st.entries and #st.entries or 0
      if count > 1 then
        vim.notify(
          ("CodeCompanion: %d pending choices for this file (use gr repeatedly to walk back)"):format(count),
          vim.log.levels.INFO
        )
      end
    end)
  end

  vim.keymap.set("n", "ga", function()
    accept_inline(bufnr)
    vim.notify("CodeCompanion: changes accepted", vim.log.levels.INFO)
  end, { buffer = bufnr, desc = "CodeCompanion: Accept changes" })

  vim.keymap.set("n", "gr", function()
    local ok, err = reject_inline(bufnr, restore_fn)
    if ok then
      vim.notify("CodeCompanion: changes rejected (reverted)", vim.log.levels.WARN)
    else
      vim.notify("CodeCompanion: reject failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end, { buffer = bufnr, desc = "CodeCompanion: Reject changes" })

  if type(show_diff_fn) == "function" then
    vim.keymap.set("n", "gv", function()
      show_diff_fn()
    end, { buffer = bufnr, desc = "CodeCompanion: View diff" })
  end

  vim.keymap.set("n", "gH", function()
    require("user.codecompanion.pending_timeline").open({ bufnr = bufnr })
  end, { buffer = bufnr, desc = "CodeCompanion: Pending timeline" })

  vim.notify("CodeCompanion: inline diff active (ga=accept, gr=reject, gv=view)", vim.log.levels.INFO)
end

local function show_diff(opts)
  -- Keep CodeCompanion's diff UI (keymaps / navigation / layout), but change the merged view
  -- so that proposed (new) lines appear above original (old) lines within each hunk.
  --
  -- Upstream implementation in `codecompanion.diff._diff_lines` merges hunks as:
  --   deletions (old) first, then additions (new).
  -- Here we build a custom merged view for this tool only:
  --   additions (new) first, then deletions (old).

  local diff_mod = require("codecompanion.diff")
  local diff_ui_mod = require("codecompanion.diff.ui")
  local cc_utils = require("codecompanion.utils")

  ---@param diff CC.Diff
  ---@return CC.Diff
  local function build_proposed_first_merged(diff)
    local hunks = diff_mod._diff(diff.from.lines, diff.to.lines) or {}

    local merged_lines = {} ---@type string[]
    local highlights = {} ---@type { row: number, type: "addition"|"deletion"|"change", word_hl?: { col: number, end_col: number }[] }[]
    local from_pos = 1
    local merged_row = 0 -- number of merged lines so far (also the 0-based index for next insertion)

    local function add_highlight(merged_row_1, type, word_ranges)
      local e = { row = merged_row_1, type = type }
      if word_ranges then
        e.word_hl = word_ranges
      end
      table.insert(highlights, e)
    end

    local function add_extmark(hunk, merged_row_1, type)
      table.insert(hunk.extmarks, { row = merged_row_1 - 1, col = 0, type = type })
    end

    for _, h in ipairs(hunks) do
      local from_start, from_count, to_start, to_count = unpack(h)
      local kind = from_count > 0 and to_count > 0 and "change" or from_count > 0 and "delete" or "add"

      local stop_at = kind == "add" and from_start or from_start - 1
      while from_pos <= stop_at do
        merged_row = merged_row + 1
        table.insert(merged_lines, diff.from.lines[from_pos])
        from_pos = from_pos + 1
      end

      ---@type CodeCompanion.diff.Hunk
      local hunk = {
        extmarks = {},
        kind = kind,
        pos = { merged_row, 0 },
        from_start = from_start,
        from_count = from_count,
        to_start = to_start,
        to_count = to_count,
      }
      table.insert(diff.hunks, hunk)

      -- For changes, compute word-level diffs (reused for both deletion/addition highlights).
      local word_diff_results = {}
      if kind == "change" then
        for i = 0, math.min(from_count, to_count) - 1 do
          local old_line = diff.from.lines[from_start + i] or ""
          local new_line = diff.to.lines[to_start + i] or ""
          local del_ranges, add_ranges = diff_mod._diff_words(old_line, new_line)
          word_diff_results[i] = { del_ranges = del_ranges, add_ranges = add_ranges }
        end
      end

      -- Add addition lines (proposed) first
      for i = 0, to_count - 1 do
        merged_row = merged_row + 1
        add_extmark(hunk, merged_row, "addition")
        table.insert(merged_lines, diff.to.lines[to_start + i])

        local word_ranges = word_diff_results[i] and word_diff_results[i].add_ranges or nil
        add_highlight(merged_row, "addition", word_ranges)
      end

      -- Then add deletion lines (original)
      for i = 0, from_count - 1 do
        merged_row = merged_row + 1
        add_extmark(hunk, merged_row, "deletion")
        table.insert(merged_lines, diff.from.lines[from_start + i])

        local word_ranges = word_diff_results[i] and word_diff_results[i].del_ranges or nil
        add_highlight(merged_row, "deletion", word_ranges)
      end

      from_pos = from_pos + from_count
    end

    while from_pos <= #diff.from.lines do
      merged_row = merged_row + 1
      table.insert(merged_lines, diff.from.lines[from_pos])
      from_pos = from_pos + 1
    end

    diff.merged = { lines = merged_lines, highlights = highlights }
    return diff
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  if opts.ft then
    local safe_ft = cc_utils.safe_filetype(opts.ft)
    vim.api.nvim_set_option_value("filetype", safe_ft, { buf = bufnr })
  end

  ---@type CC.Diff
  local diff = {
    bufnr = bufnr,
    ft = opts.ft,
    hunks = {},
    from = { lines = opts.from_lines, text = table.concat(opts.from_lines, "\n") },
    to = { lines = opts.to_lines, text = table.concat(opts.to_lines, "\n") },
    merged = { lines = {}, highlights = {} },
    marker_add = opts.marker_add,
    marker_delete = opts.marker_delete,
  }

  diff = build_proposed_first_merged(diff)

  local diff_ui = diff_ui_mod.show(diff, {
    banner = (function()
      local shared = require("codecompanion.config").interactions.shared.keymaps
      local next_key = shared.next_hunk and shared.next_hunk.modes and shared.next_hunk.modes.n or "]c"
      local prev_key = shared.previous_hunk and shared.previous_hunk.modes and shared.previous_hunk.modes.n or "[c"
      return fmt("ga Accept | gr Reject | %s/%s Next/Prev hunks | q Close", next_key, prev_key)
    end)(),
    chat_bufnr = opts.chat_bufnr,
    diff_id = math.random(10000000),
    inline = false,
    keymaps = {
      on_always_accept = function() end,
      on_accept = function()
        if opts.target_bufnr and api.nvim_buf_is_valid(opts.target_bufnr) then
          accept_inline(opts.target_bufnr)
        end
        vim.notify(fmt("Accepted edits for %s", opts.title), vim.log.levels.INFO)
      end,
      on_reject = function()
        local ok, err = true, nil
        if opts.target_bufnr and api.nvim_buf_is_valid(opts.target_bufnr) then
          ok, err = reject_inline(opts.target_bufnr, opts.restore)
        else
          ok, err = opts.restore()
        end
        if ok then
          vim.notify(fmt("Reverted edits for %s", opts.title), vim.log.levels.WARN)
        else
          vim.notify(fmt("Failed to revert edits for %s: %s", opts.title, err or "unknown"), vim.log.levels.ERROR)
        end
      end,
    },
    skip_default_keymaps = false,
    title = opts.title,
    tool_name = "insert_edit_into_file",
  })

  -- Remap accept/reject for this diff buffer only.
  -- (Keep upstream navigation keys and other defaults intact.)
  if diff_ui and diff_ui.bufnr and api.nvim_buf_is_valid(diff_ui.bufnr) then
    local shared = require("codecompanion.config").interactions.shared.keymaps
    local function del_map(map)
      if not map or not map.modes then
        return
      end
      for mode, lhs in pairs(map.modes) do
        pcall(vim.keymap.del, mode, lhs, { buffer = diff_ui.bufnr })
      end
    end
    del_map(shared.accept_change)
    del_map(shared.reject_change)

    local diff_keymaps = require("codecompanion.diff.keymaps")
    vim.keymap.set("n", "ga", function()
      diff_keymaps.accept_change.callback(diff_ui)
    end, { buffer = diff_ui.bufnr, desc = "Accept all changes", nowait = true, silent = true })

    vim.keymap.set("n", "gr", function()
      diff_keymaps.reject_change.callback(diff_ui)
    end, { buffer = diff_ui.bufnr, desc = "Reject all changes", nowait = true, silent = true })
  end
end

---@class CodeCompanion.Tool.InsertEditIntoFile: CodeCompanion.Tools.Tool
return {
  name = "insert_edit_into_file",
  ---Clear inline diff UI for a buffer.
  ---@param bufnr number
  clear_inline_visual = function(bufnr)
    clear_inline_visual(bufnr)
  end,
  ---Rehydrate inline diff after restart (pending choice).
  ---@param bufnr number
  ---@param original string
  ---@param proposed string
  ---@param meta? { filepath?: string, title?: string, ft?: string }
  rehydrate_inline_diff = function(bufnr, original, proposed, meta)
    if not bufnr or not api.nvim_buf_is_valid(bufnr) then
      return
    end
    local filepath = meta and meta.filepath or api.nvim_buf_get_name(bufnr)
    local applied_stat = filepath ~= "" and vim.uv.fs_stat(filepath) or nil
    local applied_info = {
      has_trailing_newline = (proposed or ""):match("\n$") ~= nil,
      mtime = applied_stat and applied_stat.mtime and applied_stat.mtime.sec or nil,
    }

    local function restore()
      if filepath == "" then
        return false, "No filepath"
      end
      local ok2, err2 = io_mod.write_file(filepath, original, applied_info)
      if not ok2 then
        return false, err2
      end
      if api.nvim_buf_is_valid(bufnr) then
        set_buffer_content(bufnr, original)
      end
      return true, nil
    end

    local function show_diff_fn()
      if config.display.diff.enabled ~= true then
        return
      end
      show_diff({
        chat_bufnr = nil,
        target_bufnr = bufnr,
        ft = meta and meta.ft or vim.bo[bufnr].filetype,
        from_lines = split_lines(original),
        to_lines = split_lines(proposed),
        title = meta and meta.title or vim.fn.fnamemodify(filepath, ":."),
        restore = restore,
      })
    end

    apply_inline_diff(bufnr, original, proposed, restore, show_diff_fn, false, meta)
  end,
  ---Show a pending diff in CodeCompanion's diff UI.
  ---@param entry { original: string, proposed: string, ft?: string, title?: string }
  ---@param meta? { title?: string, ft?: string, filepath?: string, index?: integer }
  show_pending_diff = function(entry, meta)
    if not entry or type(entry) ~= "table" then
      return
    end
    local original = entry.original or ""
    local proposed = entry.proposed or ""
    local ft = (meta and meta.ft) or entry.ft or "text"
    local title = (meta and meta.title) or entry.title or "pending"
    local filepath = meta and meta.filepath or nil
    local index = meta and meta.index or nil

    local diff_mod = require("codecompanion.diff")
    local diff_ui_mod = require("codecompanion.diff.ui")
    local cc_utils = require("codecompanion.utils")

    ---@param diff CC.Diff
    ---@return CC.Diff
    local function build_proposed_first_merged(diff)
      local hunks = diff_mod._diff(diff.from.lines, diff.to.lines) or {}
      local merged_lines = {} ---@type string[]
      local highlights = {} ---@type { row: number, type: "addition"|"deletion"|"change", word_hl?: { col: number, end_col: number }[] }[]
      local from_pos = 1
      local merged_row = 0

      local function add_highlight(merged_row_1, type, word_ranges)
        local e = { row = merged_row_1, type = type }
        if word_ranges then
          e.word_hl = word_ranges
        end
        table.insert(highlights, e)
      end

      local function add_extmark(hunk, merged_row_1, type)
        table.insert(hunk.extmarks, { row = merged_row_1 - 1, col = 0, type = type })
      end

      for _, h in ipairs(hunks) do
        local from_start, from_count, to_start, to_count = unpack(h)
        local kind = from_count > 0 and to_count > 0 and "change" or from_count > 0 and "delete" or "add"

        local stop_at = kind == "add" and from_start or from_start - 1
        while from_pos <= stop_at do
          merged_row = merged_row + 1
          table.insert(merged_lines, diff.from.lines[from_pos])
          from_pos = from_pos + 1
        end

        local hunk = {
          extmarks = {},
          kind = kind,
          pos = { merged_row, 0 },
          from_start = from_start,
          from_count = from_count,
          to_start = to_start,
          to_count = to_count,
        }
        table.insert(diff.hunks, hunk)

        local word_diff_results = {}
        if kind == "change" then
          for i = 0, math.min(from_count, to_count) - 1 do
            local old_line = diff.from.lines[from_start + i] or ""
            local new_line = diff.to.lines[to_start + i] or ""
            local del_ranges, add_ranges = diff_mod._diff_words(old_line, new_line)
            word_diff_results[i] = { del_ranges = del_ranges, add_ranges = add_ranges }
          end
        end

        for i = 0, to_count - 1 do
          merged_row = merged_row + 1
          add_extmark(hunk, merged_row, "addition")
          table.insert(merged_lines, diff.to.lines[to_start + i])
          local word_ranges = word_diff_results[i] and word_diff_results[i].add_ranges or nil
          add_highlight(merged_row, "addition", word_ranges)
        end

        for i = 0, from_count - 1 do
          merged_row = merged_row + 1
          add_extmark(hunk, merged_row, "deletion")
          table.insert(merged_lines, diff.from.lines[from_start + i])
          local word_ranges = word_diff_results[i] and word_diff_results[i].del_ranges or nil
          add_highlight(merged_row, "deletion", word_ranges)
        end

        from_pos = from_pos + from_count
      end

      while from_pos <= #diff.from.lines do
        merged_row = merged_row + 1
        table.insert(merged_lines, diff.from.lines[from_pos])
        from_pos = from_pos + 1
      end

      diff.merged = { lines = merged_lines, highlights = highlights }
      return diff
    end

    local bufnr = api.nvim_create_buf(false, true)
    local safe_ft = cc_utils.safe_filetype(ft)
    api.nvim_set_option_value("filetype", safe_ft, { buf = bufnr })

    local diff = {
      bufnr = bufnr,
      ft = ft,
      hunks = {},
      from = { lines = split_lines(original), text = original },
      to = { lines = split_lines(proposed), text = proposed },
      merged = { lines = {}, highlights = {} },
    }

    diff = build_proposed_first_merged(diff)

    local diff_ui = diff_ui_mod.show(diff, {
      banner = " [Pending]  ga Accept all | gr Reject to here | ]c/[c Next/Prev hunks | q Close ",
      diff_id = math.random(10000000),
      inline = false,
      skip_default_keymaps = true,
      title = title,
      tool_name = "insert_edit_into_file",
    })

    if diff_ui and diff_ui.bufnr and api.nvim_buf_is_valid(diff_ui.bufnr) then
      vim.keymap.set("n", "ga", function()
        if not filepath then
          return vim.notify("CodeCompanion: no filepath for pending accept", vim.log.levels.WARN)
        end
        local ok, err = require("user.codecompanion.pending_actions").accept_all(filepath)
        if ok then
          vim.notify("CodeCompanion: accepted all pending", vim.log.levels.INFO)
          pcall(api.nvim_win_close, diff_ui.winnr, true)
        else
          vim.notify(("CodeCompanion: accept failed: %s"):format(err or "unknown"), vim.log.levels.ERROR)
        end
      end, { buffer = diff_ui.bufnr, desc = "Accept all pending", nowait = true, silent = true })

      vim.keymap.set("n", "gr", function()
        if not filepath or not index then
          return vim.notify("CodeCompanion: no filepath/index for pending reject", vim.log.levels.WARN)
        end
        local ok, err = require("user.codecompanion.pending_actions").reject_to(filepath, index)
        if ok then
          vim.notify(("CodeCompanion: rejected pending #%d and newer"):format(index), vim.log.levels.WARN)
          pcall(api.nvim_win_close, diff_ui.winnr, true)
        else
          vim.notify(("CodeCompanion: reject failed: %s"):format(err or "unknown"), vim.log.levels.ERROR)
        end
      end, { buffer = diff_ui.bufnr, desc = "Reject to here", nowait = true, silent = true })
    end
  end,
  cmds = {
    function(self, args, opts)
      if args.edits then
        local fixed_args, error_msg = json_repair.fix_edits(args)
        if not fixed_args then
          return opts.output_cb(make_response("error", fmt("Invalid edits format: %s", error_msg)))
        end
        args = fixed_args
      end

      local path = file_utils.validate_and_normalize_path(args.filepath)
      if not path then
        return opts.output_cb(make_response("error", fmt("Error: Invalid or non-existent filepath `%s`", args.filepath)))
      end

      local bufnr = buf_utils.get_bufnr_from_path(path)
      if bufnr and api.nvim_buf_is_valid(bufnr) then
        if not api.nvim_buf_is_loaded(bufnr) then
          vim.fn.bufload(bufnr)
        end
        if vim.bo[bufnr].modified then
          return opts.output_cb(make_response("error", fmt("`%s` has unsaved changes; save it before applying edits", path)))
        end
      end

      local original_content, read_err, file_info = io_mod.read_file(path)
      if not original_content then
        return opts.output_cb(make_response("error", read_err or "Unknown error reading file"))
      end

      if #original_content > constants.LIMITS.FILE_SIZE_MAX then
        return opts.output_cb(make_response(
          "error",
          fmt(
            "Error: File too large (%d bytes). Maximum supported size is %d bytes.",
            #original_content,
            constants.LIMITS.FILE_SIZE_MAX
          )
        ))
      end

      local action = vim.deepcopy(args)
      if type(action.edits) == "string" then
        local ok, parsed = pcall(vim.json.decode, action.edits)
        if ok and type(parsed) == "table" then
          action.edits = parsed
        end
      end

      local edit = process_mod.process_edits(original_content, action.edits, { path = path, file_info = file_info, mode = action.mode })
      if not edit.success then
        local error_message = match_selector.format_helpful_error(edit, action.edits)
        return opts.output_cb(make_response("error", error_message))
      end

      local display_name = vim.fn.fnamemodify(path, ":.")
      local success_msg = fmt("Edited `%s`%s", display_name, extract_explanation(action))

      -- Apply immediately (VSCode-like: changes are present unless rejected)
      local write_ok, write_err = io_mod.write_file(path, edit.content, file_info)
      if not write_ok then
        return opts.output_cb(make_response("error", fmt("Error writing to `%s`: %s", display_name, write_err)))
      end

      if bufnr and api.nvim_buf_is_valid(bufnr) then
        set_buffer_content(bufnr, edit.content)
      end

      local applied_stat = vim.uv.fs_stat(path)
      local applied_info = {
        has_trailing_newline = file_info and file_info.has_trailing_newline,
        mtime = applied_stat and applied_stat.mtime and applied_stat.mtime.sec or nil,
      }

      opts.output_cb(make_response("success", success_msg))

      local function restore()
        -- We expect the file on disk to be the applied version at this point.
        -- Use the applied mtime as the concurrency guard (not the original mtime),
        -- otherwise a reject will always fail after we write the proposed edits.
        local ok2, err2 = io_mod.write_file(path, original_content, applied_info)
        if not ok2 then
          return false, err2
        end
        if bufnr and api.nvim_buf_is_valid(bufnr) then
          set_buffer_content(bufnr, original_content)
        end
        return true, nil
      end

      -- Inline diff in the edited buffer (VSCode-like: applied until rejected)
      if bufnr and api.nvim_buf_is_valid(bufnr) then
        local function show_diff_fn()
          if config.display.diff.enabled ~= true then
            return
          end
          show_diff({
            chat_bufnr = self.chat.bufnr,
            target_bufnr = bufnr,
            ft = vim.filetype.match({ filename = path }) or "text",
            from_lines = split_lines(original_content),
            to_lines = split_lines(edit.content),
            title = display_name,
            restore = restore,
          })
        end

        vim.schedule(function()
          apply_inline_diff(bufnr, original_content, edit.content, restore, show_diff_fn, true, {
            ft = vim.filetype.match({ filename = path }) or "text",
            title = display_name,
            explanation = action.explanation,
          })
        end)
      end
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "insert_edit_into_file",
      description = PROMPT,
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The absolute path to the file to edit, including its filename and extension",
          },
          edits = {
            type = "array",
            description = "Array of edit operations to perform sequentially",
            items = {
              type = "object",
              properties = {
                oldText = { type = "string" },
                newText = { type = "string" },
                replaceAll = { type = "boolean", default = false },
              },
              required = { "oldText", "newText", "replaceAll" },
              additionalProperties = false,
            },
          },
          mode = {
            type = "string",
            enum = { "append", "overwrite" },
            default = "append",
          },
          explanation = { type = "string" },
        },
        required = { "filepath", "edits", "explanation", "mode" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    prompt_condition = function(self, meta)
      -- Approval is controlled by config; keep upstream semantics.
      local args = self.args
      local bufnr = buf_utils.get_bufnr_from_path(args.filepath)
      if bufnr then
        if self.opts.require_approval_before and self.opts.require_approval_before.buffer then
          return true
        end
        return false
      end

      if self.opts.require_approval_before and self.opts.require_approval_before.file then
        return true
      end
      return false
    end,
  },
  output = {
    error = function(self, stderr, meta)
      if stderr then
        local chat = meta.tools.chat
        local errors = vim.iter(stderr):flatten():join("\n")
        chat:add_tool_output(self, "**Error:**\n" .. errors)
      end
    end,
    prompt = function(self, meta)
      local args = self.args
      local display_path = vim.fn.fnamemodify(args.filepath, ":.")
      local edit_count = args.edits and #args.edits or 0
      return fmt("Apply %d edit(s) to `%s`?", edit_count, display_path)
    end,
    success = function(self, stdout, meta)
      if stdout then
        local chat = meta.tools.chat
        local llm_output = vim.iter(stdout):flatten():join("\n")
        chat:add_tool_output(self, llm_output)
      end
    end,
  },
}
