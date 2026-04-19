local M = {}

local api = vim.api

local function normalize_hex(hex)
  if type(hex) ~= "string" then
    return hex
  end
  -- Allow #RRGGBBAA by dropping alpha.
  if hex:match("^#%x%x%x%x%x%x%x%x$") then
    return hex:sub(1, 7)
  end
  return hex
end

function M.apply()
  local add_bg
  local change_bg
  local delete_bg

  if vim.o.background == "light" then
    add_bg = normalize_hex("#d1fadf")
    change_bg = normalize_hex("#bff2cb")
    delete_bg = normalize_hex("#ffd6d6")
  else
    -- Dark schemes: green add / red delete. Keep them readable but not neon.
    add_bg = normalize_hex("#155a33")
    change_bg = normalize_hex("#124d2c")
    delete_bg = normalize_hex("#3a1a1a")
  end

  -- Some colorschemes set DiffAdd to red (or otherwise unexpected). Override only
  -- CodeCompanion's diff groups so the diff view stays conventional:
  -- add/change => green, delete => red.
  pcall(api.nvim_set_hl, 0, "CodeCompanionDiffAdd", { bg = add_bg, ctermbg = 22 })
  pcall(api.nvim_set_hl, 0, "CodeCompanionDiffChange", { bg = change_bg, ctermbg = 22 })
  pcall(api.nvim_set_hl, 0, "CodeCompanionDiffDelete", { bg = delete_bg, ctermbg = 52 })
end

function M.setup()
  local aug = api.nvim_create_augroup("user.codecompanion.highlights", { clear = true })
  api.nvim_create_autocmd("ColorScheme", {
    group = aug,
    callback = function()
      M.apply()
    end,
  })

  -- Apply immediately. (setup() can run after VimEnter/ColorScheme in LazyVim)
  -- Also schedule once to ensure we win over plugin-default highlight links.
  M.apply()
  vim.schedule(function()
    M.apply()
  end)
end

return M
