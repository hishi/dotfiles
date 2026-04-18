local M = {}

function M.format_title_datetime_prefix(original_title)
  if original_title == "Deciding title..." or original_title == "Refreshing title..." then
    return original_title
  end

  local title = vim.trim(original_title or "")
  local dt = os.date("%Y-%m-%d %H:%M", os.time())
  if title == "" then
    return dt
  end
  if title:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d") then
    return title
  end
  return ("%s %s"):format(dt, title)
end

function M.opts()
  return {
    auto_save = true,
    continue_last_chat = false,
    auto_generate_title = true,
    title_generation_opts = {
      format_title = M.format_title_datetime_prefix,
    },
    dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
  }
end

return M

