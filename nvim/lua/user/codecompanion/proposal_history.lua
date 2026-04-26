local M = {}

local api = vim.api
local NS = api.nvim_create_namespace("user.codecompanion.proposal_history")
local actions = require("user.codecompanion.proposal_history.actions")
local render = require("user.codecompanion.proposal_history.render")

local function create_history_buf(display_path)
  local history_buf = api.nvim_create_buf(false, true)
  pcall(api.nvim_buf_set_name, history_buf, ("CodeCompanionProposalHistory:%s"):format(display_path))
  api.nvim_set_option_value("buftype", "nofile", { buf = history_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = history_buf })
  api.nvim_set_option_value("swapfile", false, { buf = history_buf })
  api.nvim_set_option_value("modifiable", true, { buf = history_buf })
  api.nvim_set_option_value("filetype", "codecompanion", { buf = history_buf })
  return history_buf
end

local function open_window(layout, history_buf)
  local win
  if layout == "split" then
    vim.cmd("botright vsplit")
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, history_buf)
    pcall(api.nvim_win_set_width, win, math.min(120, math.max(80, math.floor(vim.o.columns * 0.45))))
    pcall(api.nvim_set_option_value, "winfixwidth", true, { win = win })
    pcall(api.nvim_set_option_value, "wrap", false, { win = win })
  else
    local width = math.min(math.max(90, math.floor(vim.o.columns * 0.75)), vim.o.columns - 4)
    local height = math.min(math.max(25, math.floor(vim.o.lines * 0.75)), vim.o.lines - 6)
    local row = math.floor((vim.o.lines - height) / 2) - 1
    local col = math.floor((vim.o.columns - width) / 2)
    win = api.nvim_open_win(history_buf, true, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      width = width,
      height = height,
      row = math.max(row, 0),
      col = math.max(col, 0),
      title = " CodeCompanion Proposal History ",
      title_pos = "center",
    })
  end
  return win
end

---@param opts? { filepath?: string, bufnr?: number, layout?: "split"|"float" }
function M.open(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or api.nvim_get_current_buf()
  local filepath = opts.filepath or api.nvim_buf_get_name(bufnr)
  if not filepath or filepath == "" then
    return vim.notify("CodeCompanion: no file for proposal history", vim.log.levels.WARN)
  end

  local pe = require("user.codecompanion.pending_edits")
  local ph = require("user.codecompanion.pending_history")
  local pending_entry = pe.peek(filepath)
  if not pending_entry then
    return vim.notify("CodeCompanion: no active pending proposal", vim.log.levels.INFO)
  end

  local history_state = ph.get(filepath)
  local history_entries = (history_state and history_state.entries) or {}
  local visible_history_entries = render.filter_history_entries(pending_entry, history_entries)
  local view = render.build(filepath, pending_entry, visible_history_entries)

  local history_buf = create_history_buf(view.display_path)
  api.nvim_buf_set_lines(history_buf, 0, -1, false, view.lines)
  api.nvim_set_option_value("modifiable", false, { buf = history_buf })

  api.nvim_buf_clear_namespace(history_buf, NS, 0, -1)
  for row0, hl in ipairs(view.line_hls) do
    if hl ~= "" then
      pcall(api.nvim_buf_set_extmark, history_buf, NS, row0 - 1, 0, {
        line_hl_group = hl,
        priority = 200,
      })
    end
  end

  local layout = opts.layout or "float"
  local win = open_window(layout, history_buf)

  pcall(api.nvim_set_option_value, "foldmethod", "marker", { win = win })
  pcall(api.nvim_set_option_value, "foldmarker", "{{{,}}}", { win = win })
  pcall(api.nvim_set_option_value, "foldlevel", 1, { win = win })

  actions.attach({
    history_buf = history_buf,
    win = win,
    entry_spans = view.entry_spans,
    filepath = filepath,
  })
end

return M
