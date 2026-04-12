local M = {}

local URL = "https://api.github.com/copilot_internal/user"

function M.format_premium_label(json, opts)
  opts = opts or {}
  local prefix = opts.prefix or "Premium"
  local show_reset = opts.show_reset or false
  local reset_date = show_reset and json and json.quota_reset_date or nil

  local premium = json and json.quota_snapshots and json.quota_snapshots.premium_interactions or nil
  if not premium then
    return nil
  end

  local suffix = reset_date and (" / リセット: " .. reset_date) or ""
  if premium.unlimited then
    return string.format("%s: Unlimited%s", prefix, suffix)
  end

  if type(premium.entitlement) == "number" and type(premium.remaining) == "number" then
    local used = premium.entitlement - premium.remaining
    return string.format("%s: %d/%d（残り %d）%s", prefix, used, premium.entitlement, premium.remaining, suffix)
  end
end

local function decode_json(body)
  local ok, json = pcall(vim.json.decode, body)
  if not ok or type(json) ~= "table" then
    return nil, { kind = "json" }
  end
  return json, nil
end

local function parse_response(resp, opts)
  if not resp or type(resp.body) ~= "string" then
    return nil, { kind = "no_body" }
  end

  if opts.check_status ~= false and resp.status ~= 200 then
    return nil, { kind = "http", status = resp.status }
  end

  return decode_json(resp.body)
end

local function request(Curl, auth_header, opts, cb)
  return Curl.get(URL, {
    sync = opts.sync or false,
    headers = {
      Authorization = auth_header,
      Accept = "*/*",
      ["User-Agent"] = opts.user_agent or "nvim",
    },
    timeout = opts.timeout,
    proxy = opts.proxy,
    insecure = opts.insecure,
    callback = cb,
  })
end

local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[k] = v
  end
  return out
end

function M.make_quota_updater(opts)
  local state = {
    inflight = false,
    last_fetch_ms = 0,
  }

  local cooldown_ms = opts.cooldown_ms or 5000
  local loading_label = opts.loading_label

  local function should_fetch()
    local now_ms = vim.uv.now()
    if state.inflight then
      return false
    end
    if state.last_fetch_ms ~= 0 and now_ms - state.last_fetch_ms < cooldown_ms then
      return false
    end
    state.last_fetch_ms = now_ms
    state.inflight = true
    return true
  end

  local function done()
    state.inflight = false
  end

  local function render(line)
    if opts.render then
      local ok = pcall(opts.render, line)
      if not ok then
        -- Don't let UI rendering errors wedge inflight state.
      end
    end
  end

  return function()
    if not should_fetch() then
      return
    end

    local function fail(err)
      done()
      if opts.on_error then
        pcall(opts.on_error, err)
      end
    end

    local function fail_auth(auth_err)
      done()
      if auth_err and opts.on_auth_error then
        pcall(opts.on_auth_error, auth_err)
        return
      end
      if opts.on_error then
        pcall(opts.on_error, { kind = "no_auth" })
      end
    end

    if loading_label then
      render(loading_label)
    end

    local auth_headers, auth_err = nil, nil
    if opts.get_auth_headers then
      local ok, a, e = pcall(opts.get_auth_headers)
      if not ok then
        return fail({ kind = "exception" })
      end
      auth_headers, auth_err = a, e
    end
    if not auth_headers or not auth_headers[1] then
      return fail_auth(auth_err)
    end

    local fetch_opts = nil
    if type(opts.fetch_opts) == "function" then
      local ok, v = pcall(opts.fetch_opts)
      if not ok then
        return fail({ kind = "exception" })
      end
      fetch_opts = v
    else
      fetch_opts = opts.fetch_opts
    end
    if type(fetch_opts) ~= "table" then
      fetch_opts = {}
    end
    fetch_opts = vim.tbl_extend("force", shallow_copy(fetch_opts), { auth_headers = auth_headers })

    local function on_result(json, err)
      done()
      if err then
        if opts.on_error then
          pcall(opts.on_error, err)
        end
        return
      end
      if not json then
        return
      end

      local line = nil
      if opts.format then
        local ok, v = pcall(opts.format, json)
        if ok then
          line = v
        else
          return
        end
      end
      if line then
        render(line)
      end
    end

    if opts.mode == "sync" then
      local json, err = M.fetch_sync(fetch_opts)
      return on_result(json, err)
    end

    return M.fetch_async(fetch_opts, on_result)
  end
end

function M.fetch_sync(opts)
  local Curl = require("plenary.curl")
  local headers = opts.auth_headers or {}
  local auth_header = headers[1] or opts.auth_header
  if not auth_header then
    return nil, { kind = "no_auth" }
  end

  opts = vim.tbl_extend("force", shallow_copy(opts), { sync = true })

  local resp = request(Curl, auth_header, opts, nil)
  if headers[2] and resp and (resp.status == 401 or resp.status == 403) then
    resp = request(Curl, headers[2], opts, nil)
  end
  return parse_response(resp, opts)
end

function M.fetch_async(opts, cb)
  local Curl = require("plenary.curl")
  local headers = opts.auth_headers or {}
  local auth_header = headers[1] or opts.auth_header
  if not auth_header then
    return cb(nil, { kind = "no_auth" })
  end

  opts = vim.tbl_extend("force", shallow_copy(opts), { sync = false })

  local function done(resp)
    return cb(parse_response(resp, opts))
  end

  local function first(resp)
    if headers[2] and resp and (resp.status == 401 or resp.status == 403) then
      return request(Curl, headers[2], opts, done)
    end
    return done(resp)
  end

  request(Curl, auth_header, opts, first)
end

return M
