local M = {}

local redoc_image = "redocly/redoc:v2.5.3"
local active_task
local active_url
local active_container
local active_index

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "OpenAPI preview" })
end

local function current_spec()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local extension = vim.fn.fnamemodify(path, ":e"):lower()

  if path == "" or not vim.tbl_contains({ "yaml", "yml", "json" }, extension) then
    notify("Open an OpenAPI YAML or JSON file first", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sample = table.concat(vim.list_slice(lines, 1, 100), "\n")
  if not sample:match("[\"']?openapi[\"']?%s*:") and not sample:match("[\"']?swagger[\"']?%s*:") then
    notify("The current file does not look like an OpenAPI document", vim.log.levels.WARN)
    return
  end

  local content = table.concat(lines, "\n")
  if content:match("%$ref%s*:%s*[\"']?https?://") then
    notify("External $ref URLs are disabled for an offline preview", vim.log.levels.ERROR)
    return
  end

  if vim.bo[bufnr].modified then
    local ok, err = pcall(vim.cmd.update)
    if not ok then
      notify("Could not save the OpenAPI file: " .. err, vim.log.levels.ERROR)
      return
    end
  end

  return vim.fs.normalize(path)
end

local function stop_container()
  if active_task and active_task:is_running() then
    active_task:stop()
  end
  if active_container and vim.fn.executable("docker") == 1 then
    vim.system({ "docker", "rm", "--force", active_container }, { text = true }):wait(5000)
  end
  if active_index then
    vim.uv.fs_unlink(active_index)
  end
  active_task = nil
  active_container = nil
  active_index = nil
end

local function write_index(spec_name)
  local assets_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "openapi-preview")
  vim.fn.mkdir(assets_dir, "p")
  local path = vim.fs.joinpath(assets_dir, tostring(vim.uv.hrtime()) .. "-redoc.html")
  local spec_url = "/spec/" .. spec_name:gsub("%%", "%%25"):gsub(" ", "%%20")
  local html = ([=[
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'self'; connect-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>OpenAPI Preview</title>
    <style>body { margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }</style>
  </head>
  <body>
    <redoc spec-url=%s disable-telemetry="true"></redoc>
    <script src="/redoc.standalone.js"></script>
    <script>
      let previous
      const refresh = async () => {
        const response = await fetch(`${%s}?_=${Date.now()}`, { cache: 'no-store' })
        const current = await response.text()
        if (previous !== undefined && current !== previous) location.reload()
        previous = current
      }
      refresh()
      window.setInterval(refresh, 1000)
    </script>
  </body>
</html>
]=]):format(vim.json.encode(spec_url), vim.json.encode(spec_url))

  local ok, err = pcall(vim.fn.writefile, vim.split(html, "\n"), path)
  if not ok then
    notify("Could not create the offline Redoc page: " .. err, vim.log.levels.ERROR)
    return
  end
  return path
end

local function open_when_ready(task, url, attempts)
  if task ~= active_task or not task:is_running() then
    return
  end
  if attempts <= 0 then
    notify("Redoc did not start; check the task with <leader>Ot", vim.log.levels.ERROR)
    return
  end

  vim.system({ "curl", "--silent", "--fail", "--max-time", "1", url }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.ui.open(url)
        notify("Offline Redoc preview ready at " .. url)
      else
        vim.defer_fn(function()
          open_when_ready(task, url, attempts - 1)
        end, 500)
      end
    end)
  end)
end

local function check_docker()
  if vim.fn.executable("docker") ~= 1 then
    notify("Docker is required for the offline Redoc preview", vim.log.levels.ERROR)
    return false
  end

  local docker_info = vim.system({ "docker", "info" }, { text = true }):wait(5000)
  if docker_info.code ~= 0 then
    notify("Docker is not running. Start Colima first", vim.log.levels.ERROR)
    return false
  end

  local image = vim.system({ "docker", "image", "inspect", redoc_image }, { text = true }):wait(5000)
  if image.code ~= 0 then
    notify("Redoc image is missing; run: docker pull " .. redoc_image, vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.start()
  local path = current_spec()
  if not path or not check_docker() then
    return
  end

  stop_container()

  local port = vim.g.openapi_preview_port or 8080
  active_url = ("http://127.0.0.1:%d/offline.html"):format(port)
  active_container = ("nvim-openapi-preview-%d"):format(port)
  active_index = write_index(vim.fs.basename(path))
  if not active_index then
    return
  end

  local task = require("overseer").new_task({
    name = "OpenAPI preview: " .. vim.fs.basename(path),
    cmd = {
      "docker",
      "run",
      "--rm",
      "--pull",
      "never",
      "--name",
      active_container,
      "--publish",
      ("127.0.0.1:%d:80"):format(port),
      "--env",
      "SPEC_URL=spec/" .. vim.fs.basename(path),
      "--env",
      "PAGE_TITLE=OpenAPI Preview",
      "--env",
      'REDOC_OPTIONS=disable-telemetry="true"',
      "--env",
      "REDOCLY_TELEMETRY=off",
      "--volume",
      vim.fs.dirname(path) .. ":/usr/share/nginx/html/spec:ro",
      "--volume",
      active_index .. ":/usr/share/nginx/html/offline.html:ro",
      redoc_image,
    },
    components = { "default" },
  })

  active_task = task
  task:start()
  notify("Starting offline Redoc")
  open_when_ready(task, active_url, 120)
end

function M.open()
  if not active_url or not active_task or not active_task:is_running() then
    notify("No OpenAPI preview is running", vim.log.levels.WARN)
    return
  end
  vim.ui.open(active_url)
end

function M.stop(silent)
  local running = active_task and active_task:is_running()
  stop_container()
  if running and not silent then
    notify("Preview stopped")
  elseif not silent then
    notify("No OpenAPI preview is running", vim.log.levels.WARN)
  end
end

function M.setup()
  vim.api.nvim_create_user_command("OpenApiPreview", M.start, { desc = "Preview the current OpenAPI file" })
  vim.api.nvim_create_user_command("OpenApiPreviewOpen", M.open, { desc = "Open the current OpenAPI preview" })
  vim.api.nvim_create_user_command("OpenApiPreviewStop", function()
    M.stop()
  end, { desc = "Stop the current OpenAPI preview" })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.stop(true)
    end,
  })
end

return M
