local M = {}

local function datetime_prefix_from_save_id(save_id)
  if not save_id then
    return os.date("%Y-%m-%d %H:%M", os.time())
  end

  local id_num = tonumber(save_id)
  if not id_num then
    return os.date("%Y-%m-%d %H:%M", os.time())
  end

  -- Some operations (e.g. duplicate) can use millisecond-ish ids.
  if id_num > 1000000000000 then
    id_num = math.floor(id_num / 1000)
  end

  return os.date("%Y-%m-%d %H:%M", id_num)
end

function M.prefix_datetime_title(chat)
  if not chat or not chat.opts then
    return
  end

  if not chat.opts.save_id then
    chat.opts.save_id = tostring(os.time())
  end

  local prefix = datetime_prefix_from_save_id(chat.opts.save_id)
  local title = chat.opts.title

  if not title or title == "" then
    chat.opts.title = prefix
    return
  end

  if title:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d") then
    return
  end

  chat.opts.title = ("%s %s"):format(prefix, title)
end

return M
