local function show_winbar_pane(direction)
  local config = require("kulala.config").get()
  local panes = config.default_winbar_panes or {}
  local current_view = config.default_view

  if #panes == 0 then
    return
  end

  if type(current_view) == "function" then
    current_view = panes[1]
  end

  local current_index = 1
  for index, pane in ipairs(panes) do
    if pane == current_view then
      current_index = index
      break
    end
  end

  local next_index = ((current_index - 1 + direction) % #panes) + 1
  local show_pane = require("kulala.ui")["show_" .. panes[next_index]]

  if show_pane then
    show_pane()
  end
end

return {
  "mistweaverco/kulala.nvim",
  keys = {
    -- { "<leader>Rs", desc = "Send request" },
    -- { "<leader>Ra", desc = "Send all requests" },
    -- { "<leader>Rb", desc = "Open scratchpad" },
  },
  ft = {"http", "rest"},
  opts = {
    global_keymaps = true,
    global_keymaps_prefix = "<leader>R",
    kulala_keymaps_prefix = "<leader>k",
    kulala_keymaps = {
      ["Previous tab"] = {
        "H",
        function()
          show_winbar_pane(-1)
        end,
      },
      ["Next tab"] = {
        "L",
        function()
          show_winbar_pane(1)
        end,
      },
    },
    ui = {
      display_mode = "float",
      default_view = "body",
      max_response_size = 1024 * 1024, -- 1MB
    }
  },
}
