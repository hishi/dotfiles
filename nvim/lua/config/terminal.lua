local M = {}

local function is_terminal(term)
  return term and term.buf and vim.api.nvim_buf_is_valid(term.buf)
end

local function restore_insert()
  if vim.bo.buftype == "terminal" then
    vim.cmd.startinsert()
  end
end

local function apply_float(term)
  term.opts.position = "float"
  term.opts.relative = "editor"
  term.opts.win = nil
  term.opts.width = 0.9
  term.opts.height = 0.9
  term.opts.border = "rounded"
  term.opts.backdrop = term.opts.backdrop == false and 60 or term.opts.backdrop
  term.opts.wo = term.opts.wo or {}
  term.opts.wo.winbar = ""
end

local function apply_split(term)
  local info = vim.b[term.buf].snacks_terminal or {}

  term.opts.position = "bottom"
  term.opts.relative = "editor"
  term.opts.win = nil
  term.opts.height = 0.35
  term.opts.backdrop = false
  term.opts.border = nil
  term.opts.wo = term.opts.wo or {}
  term.opts.wo.winbar = ("%s: %%{get(b:, 'term_title', '')}"):format(info.id or vim.v.count1)
end

local function show_as(term, layout)
  if not is_terminal(term) then
    return
  end

  local current = vim.api.nvim_get_current_buf()
  local was_current = current == term.buf
  local was_terminal_mode = vim.fn.mode():sub(1, 1) == "t"

  if term:valid() then
    term:hide()
  end

  if layout == "split" then
    apply_split(term)
  else
    apply_float(term)
  end

  term:show():focus()

  if was_current or was_terminal_mode then
    vim.schedule(restore_insert)
  end
end

function M.float(cwd)
  local term, created = Snacks.terminal.get(nil, {
    cwd = cwd,
    win = {
      position = "float",
      width = 0.9,
      height = 0.9,
      border = "rounded",
    },
  })

  if not is_terminal(term) then
    return
  end

  if not created and term:valid() and vim.api.nvim_get_current_buf() == term.buf and term:is_floating() then
    term:hide()
    return
  end

  show_as(term, "float")
end

function M.split(cwd)
  local term = Snacks.terminal.get(nil, {
    cwd = cwd,
    win = {
      position = "bottom",
      height = 0.35,
    },
  })

  show_as(term, "split")
end

function M.toggle_layout(term)
  if not is_terminal(term) then
    return
  end

  show_as(term, term:is_floating() and "split" or "float")
end

return M
