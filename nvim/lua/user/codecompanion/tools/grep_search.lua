local function default_include_pattern(cwd)
  if vim.fn.isdirectory(vim.fs.joinpath(cwd, "app")) == 1 then
    return "app/**"
  end
  if vim.fn.isdirectory(vim.fs.joinpath(cwd, "src")) == 1 then
    return "src/**"
  end
  return nil
end

local base = require("codecompanion.interactions.chat.tools.builtin.grep_search")

local base_cmd = base.cmds[1]
base.cmds[1] = function(self, args, input)
  if type(args) == "table" and (args.include_pattern == nil or args.include_pattern == "") then
    args.include_pattern = default_include_pattern(vim.fn.getcwd())
  end
  return base_cmd(self, args, input)
end

return base
