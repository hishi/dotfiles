local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local ignore = require("user.codecompanion.tools.ignore")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Search the current working directory for text using ripgrep
---@param action { query: string, is_regexp: boolean?, include_pattern: string? }
---@param opts table
---@return { status: "success"|"error", data: string|table }
local function grep_search(action, opts)
  opts = opts or {}
  local query = action.query

  if not query or query == "" then
    return { status = "error", data = "Query parameter is required and cannot be empty" }
  end

  if vim.fn.executable("rg") ~= 1 then
    return { status = "error", data = "ripgrep (rg) is not installed or not in PATH" }
  end

  local cmd = { "rg" }
  local cwd = vim.fn.getcwd()
  local max_results = opts.max_results or 100
  local is_regexp = action.is_regexp or false

  local respect_gitignore = ignore.respect_gitignore(opts)

  table.insert(cmd, "--json")
  table.insert(cmd, "--line-number")
  table.insert(cmd, "--no-heading")
  table.insert(cmd, "--with-filename")

  -- Include dotfolders like `.vscode/` (still excluded via glob rules below).
  table.insert(cmd, "--hidden")

  if not is_regexp then
    table.insert(cmd, "--fixed-strings")
  end

  table.insert(cmd, "--ignore-case")

  if not respect_gitignore then
    table.insert(cmd, "--no-ignore")
  end

  if action.include_pattern and action.include_pattern ~= "" then
    table.insert(cmd, "--glob")
    table.insert(cmd, action.include_pattern)
  end

  for _, glob in ipairs(ignore.rg_exclude_globs(opts.exclude_globs)) do
    table.insert(cmd, "--glob")
    table.insert(cmd, glob)
  end

  table.insert(cmd, "--max-count")
  table.insert(cmd, tostring(math.min(max_results, 50)))

  table.insert(cmd, "-e")
  table.insert(cmd, query)
  table.insert(cmd, cwd)

  log:debug("[Grep Search Tool] Running command: %s", table.concat(cmd, " "))

  local result = vim
    .system(cmd, { text = true, timeout = 30000 })
    :wait()

  if result.code ~= 0 then
    local error_msg = result.stderr or "Unknown error"
    if result.code == 1 then
      return { status = "success", data = "No matches found for the query" }
    elseif result.code == 2 then
      return {
        status = "error",
        data = fmt("Invalid search pattern or arguments: %s", error_msg:match("^[^\n]*") or "Unknown error"),
      }
    else
      return { status = "error", data = fmt("Search failed: %s", error_msg:match("^[^\n]*") or "Unknown error") }
    end
  end

  local output = result.stdout or ""
  if output == "" then
    return { status = "success", data = "No matches found for the query" }
  end

  local matches = {}
  local count = 0
  for line in output:gmatch("[^\n]+") do
    if count >= max_results then
      break
    end
    local ok, json_data = pcall(vim.json.decode, line)
    if ok and json_data.type == "match" then
      local file_path = json_data.data.path.text
      local line_number = json_data.data.line_number
      table.insert(matches, fmt("%s:%d", file_path, line_number))
      count = count + 1
    end
  end

  if #matches == 0 then
    return { status = "success", data = "No matches found for the query" }
  end

  return { status = "success", data = matches }
end

---@class CodeCompanion.Tool.GrepSearch: CodeCompanion.Tools.Tool
return {
  name = "grep_search",
  cmds = {
    function(self, args)
      return grep_search(args, self.tool.opts)
    end,
  },
  schema = {
    ["function"] = {
      name = "grep_search",
      description = "Do a text search in the workspace.",
      parameters = {
        type = "object",
        properties = {
          query = { type = "string", description = "The pattern to search for in files in the workspace." },
          is_regexp = { type = "boolean", description = "Whether the pattern is a regex. False by default." },
          include_pattern = {
            type = "string",
            description = "Search files matching this glob pattern. Applied to relative paths.",
          },
        },
        required = { "query" },
      },
    },
    type = "function",
  },
  output = {
    cmd_string = function(self, opts)
      return self.args.query or ""
    end,
    prompt = function(self, meta)
      return fmt("Grep search for `%s`?", self.args.query)
    end,
    success = function(self, stdout, meta)
      local query = self.args.query
      local chat = meta.tools.chat
      local data = stdout[1]

      local llm_output = [[<grepSearchTool>%s

NOTE:
- The output format is {filepath}:{line_number}.
- For example:
/Users/user/project/lua/codecompanion/interactions/chat/tools/init.lua:335
Refers to line 335 of the init.lua file</grepSearchTool>]]
      local output = vim.iter(stdout):flatten():join("\n")

      if type(data) == "table" then
        local results = #data
        local results_msg = fmt("Searched text for `%s`, %d results\n```\n%s\n```", query, results, output)
        chat:add_tool_output(self, fmt(llm_output, results_msg), results_msg)
      else
        local no_results_msg = fmt("Searched text for `%s`, no results", query)
        chat:add_tool_output(self, fmt(llm_output, no_results_msg), no_results_msg)
      end
    end,
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local query = self.args.query
      local errors = vim.iter(stderr):flatten():join("\n")
      local error_output = fmt(
        [[Searched text for `%s`, error:
```
%s
```]],
        query,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,
    rejected = function(self, meta)
      local message = "The user rejected the grep search tool"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}
