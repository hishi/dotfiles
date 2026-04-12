local M = {}

local URL_PATTERN = "https?://[%w%-._~:/?#%[%]@!$&'()*+,;=%%]+"

local function trim_url(url)
  url = url:gsub("^[<(%[{\"']", "")
  url = url:gsub("[>%)%]}\"'.,;:!?]+$", "")
  return url
end

local function url_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local start = 1

  while true do
    local from, to = line:find(URL_PATTERN, start)
    if not from then
      break
    end

    if from <= col and col <= to then
      return trim_url(line:sub(from, to))
    end

    start = to + 1
  end

  local cfile = vim.fn.expand("<cfile>")
  if cfile:match("^https?://") then
    return trim_url(cfile)
  end
end

function M.open_url()
  local url = url_at_cursor()
  if not url then
    vim.notify("No URL found under cursor", vim.log.levels.WARN)
    return
  end

  local ok, result = pcall(vim.ui.open, url)
  if not ok then
    vim.notify(("Failed to open URL: %s"):format(result), vim.log.levels.ERROR)
    return
  end

  if result and result.code ~= 0 then
    local message = result.stderr ~= "" and result.stderr or ("exit code %d"):format(result.code)
    vim.notify(("Failed to open URL: %s"):format(message), vim.log.levels.ERROR)
  end
end

return M
