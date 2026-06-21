local M = {}

-- OneNoteでページを右クリックし、コピーしたリンクを登録してください。
-- パスワードなどの秘密情報ではなく、ページへのリンクだけを置きます。
M.pages = {
  -- ["認証情報"] = "https://...",
  -- ["作業メモ"] = "https://...",
}

local function page_names()
  local names = vim.tbl_keys(M.pages)
  table.sort(names)
  return names
end

local function open_page(name)
  local url = M.pages[name]
  if not url then
    vim.notify(("Unknown OneNote page: %s"):format(name), vim.log.levels.ERROR)
    return
  end

  local ok, process_or_error, err = pcall(vim.ui.open, url)
  if not ok then
    vim.notify(("Failed to open OneNote page: %s"):format(process_or_error), vim.log.levels.ERROR)
    return
  end

  if err then
    vim.notify(("Failed to open OneNote page: %s"):format(err), vim.log.levels.ERROR)
  end
end

function M.open(name)
  if name and name ~= "" then
    open_page(name)
    return
  end

  local names = page_names()
  if #names == 0 then
    vim.notify("No OneNote pages configured in lua/config/onenote.lua", vim.log.levels.WARN)
    return
  end

  vim.ui.select(names, { prompt = "OneNote page:" }, function(choice)
    if choice then
      open_page(choice)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("OneNote", function(opts)
    M.open(opts.args)
  end, {
    nargs = "?",
    complete = function()
      return page_names()
    end,
    desc = "Open a configured OneNote page",
  })
end

return M
