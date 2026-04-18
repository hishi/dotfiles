local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local ignore = require("user.codecompanion.tools.ignore")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Search the current working directory for files matching the glob pattern using ripgrep.
---@param action { query: string, max_results: number? }
---@param opts table
---@return { status: "success"|"error", data: string|table }
local function file_search(action, opts)
  opts = opts or {}
  local query = action.query

  local max_results = action.max_results or opts.max_results or 500
  if not query or query == "" then
    return { status = "error", data = "Query parameter is required and cannot be empty" }
  end

  if vim.fn.executable("rg") ~= 1 then
    return { status = "error", data = "ripgrep (rg) is not installed or not in PATH" }
  end

  local cmd = { "rg", "--files" }
  local cwd = vim.fn.getcwd()

  -- Include dotfiles (e.g. `.vscode/`) unless excluded by globs/gitignore.
  table.insert(cmd, "--hidden")

  local respect_gitignore = opts.respect_gitignore
  if respect_gitignore == nil then
    respect_gitignore = opts.respect_gitignore ~= false
  end
  if not respect_gitignore then
    table.insert(cmd, "--no-ignore")
  end

  table.insert(cmd, "--glob")
  table.insert(cmd, query)

  for _, glob in ipairs(ignore.rg_exclude_globs(opts.exclude_globs)) do
    table.insert(cmd, "--glob")
    table.insert(cmd, glob)
  end

  table.insert(cmd, cwd)

  log:debug("[File Search Tool] Running command: %s", table.concat(cmd, " "))

  local result = vim
    .system(cmd, { text = true, timeout = 30000 })
    :wait()

  if result.code ~= 0 then
    local error_msg = result.stderr or "Unknown error"
    log:warn("[File Search Tool] Command failed with code %d: %s", result.code, error_msg)
    return { status = "error", data = fmt("Search failed: %s", error_msg:match("^[^\n]*") or "Unknown error") }
  end

  local output = vim.trim(result.stdout or "")
  if output == "" then
    return { status = "success", data = fmt("No files found matching pattern '%s'", query) }
  end

  local files = {}
  for line in output:gmatch("[^\n]+") do
    if #files >= max_results then
      break
    end
    table.insert(files, line)
  end

  if #files == 0 then
    return { status = "success", data = fmt("No files found matching pattern '%s'", query) }
  end

  return { status = "success", data = files }
end

---@class CodeCompanion.Tool.FileSearch: CodeCompanion.Tools.Tool
return {
  name = "file_search",
  cmds = {
    function(self, args, input)
      return file_search(args, self.tool.opts)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "file_search",
      description = "Search for files in the workspace by glob pattern. This only returns the paths of matching files.",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "Search for files with names or paths matching this glob pattern.",
          },
          max_results = {
            type = "number",
            description = "The maximum number of results to return.",
          },
        },
        required = { "query" },
      },
    },
  },
  handlers = {
    on_exit = function(self, meta) end,
  },
  output = {
    cmd_string = function(self, meta)
      return self.args.query
    end,
    prompt = function(self, meta)
      return fmt("Search the cwd for `%s`?", self.args.query)
    end,
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local query = self.args.query
      local data = stdout[1]
      local llm_output = "<fileSearchTool>%s</fileSearchTool>"
      local output = vim.iter(stdout):flatten():join("\n")

      if type(data) == "table" then
        local files = #data
        local results_msg = fmt("Searched files for `%s`, %d results\n```\n%s\n```", query, files, output)
        chat:add_tool_output(self, fmt(llm_output, results_msg), results_msg)
      else
        local no_results_msg = fmt("Searched files for `%s`, no results", query)
        chat:add_tool_output(self, fmt(llm_output, no_results_msg), no_results_msg)
      end
    end,
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local query = self.args.query
      local errors = vim.iter(stderr):flatten():join("\n")
      local error_output = fmt(
        [[Searched files for `%s`, error:

```txt
%s
```]],
        query,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,
    rejected = function(self, meta)
      local message = "The user rejected the file search tool"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}

