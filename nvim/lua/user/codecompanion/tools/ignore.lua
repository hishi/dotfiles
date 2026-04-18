local M = {}

-- Directories that are almost always noise for searching in typical dev repos.
-- Keep this list conservative; avoid excluding user config like `.vscode/`.
M.default_excluded_dirs = {
  ".git",
  "node_modules",
  ".next",
  ".turbo",
  "build",
  "coverage",
  ".terraform",
  ".terragrunt-cache",
  "__pycache__",
  ".pytest_cache",
  ".mypy_cache",
  ".ruff_cache",
  ".venv",
  "venv",
  ".bundle",
  "tmp",
  "log",
}

function M.rg_exclude_globs(extra)
  local globs = {}

  for _, dir in ipairs(M.default_excluded_dirs) do
    table.insert(globs, ("!**/%s/**"):format(dir))
  end

  for _, g in ipairs(extra or {}) do
    if type(g) == "string" and g ~= "" then
      table.insert(globs, g)
    end
  end

  return globs
end

return M
