return { -- avante.nvimの設定（一部省略）
  {
    "yetone/avante.nvim",
    opts = {
      provider = "copilot",
      auto_suggestions_provider = nil,
      behaviour = {
        auto_focus_sidebar = false,
        auto_set_keymaps = true,
        auto_add_current_file = true,
        enable_token_counting = true,
      },
      input = {
        provider = "snacks",
        provider_opts = {
          title = "Avante",
        },
      },
      selector = {
        provider = "snacks",
      },
      mappings = {
        ask = "<leader>aa",
        new_ask = "<leader>an",
        edit = "<leader>ae",
        refresh = "<leader>ar",
        focus = "<leader>af",
        stop = "<leader>aS",
        toggle = {
          default = "<leader>at",
          suggestion = "<leader>as",
          repomap = "<leader>aR",
        },
        files = {
          add_current = "<leader>ac",
          add_all_buffers = "<leader>aB",
        },
        select_model = "<leader>am",
        select_history = "<leader>ah",
        sidebar = {
          switch_windows = "<C-j>",
          reverse_switch_windows = "<C-k>",
          apply_all = "A",
          apply_cursor = "a",
          retry_user_request = "r",
          edit_user_request = "e",
          add_file = "@",
          remove_file = "d",
          close = { "q", "<Esc>" },
        },
      },
      windows = {
        position = "right",
        width = 38,
        wrap = true,
        sidebar_header = {
          enabled = true,
          align = "center",
          rounded = true,
          include_model = true,
        },
        input = {
          height = 10,
        },
        ask = {
          floating = false,
          start_insert = true,
          border = "rounded",
        },
        edit = {
          border = "rounded",
          start_insert = true,
        },
      },
      providers = {
        copilot = {
          endpoint = "https://api.githubcopilot.com",
          -- model = "claude-sonnet-4.5",
          model = "gpt-5-mini",
        },
      },
    },
    config = function(_, opts)
      require("avante").setup(opts)

      local Sidebar = require("avante.sidebar")
      local Utils = require("avante.utils")
      local Config = require("avante.config")
      local Providers = require("avante.providers")
      local InternalUser = require("copilot_internal_user")

      -- Copilot premium requests quota (internal API; may break if GitHub changes it)
      if not Sidebar.__copilot_quota_patched then
        Sidebar.__copilot_quota_patched = true

        local QUOTA_COOLDOWN_MS = 5000
        local function rerender(sidebar)
          if Utils.is_valid_container(sidebar.containers.result, true) then
            sidebar:render_result()
          end
        end

        local function get_oauth_token()
          local Path = require("plenary.path")
          local config_dir = vim.fn.expand("~/.config/github-copilot")

          for _, filename in ipairs({ "hosts.json", "apps.json" }) do
            local p = Path:new(config_dir):joinpath(filename)
            if p:exists() then
              local ok, decoded = pcall(vim.json.decode, p:read())
              if not ok or type(decoded) ~= "table" then
                return nil, "OAuthトークンの読み取りに失敗しました"
              end

              for k, v in pairs(decoded) do
                if
                  type(k) == "string"
                  and k:match("github.com")
                  and type(v) == "table"
                  and type(v.oauth_token) == "string"
                then
                  return v.oauth_token, nil
                end
              end

              return nil, "OAuthトークンが見つかりません"
            end
          end

          return nil, "hosts.json/apps.json が見つかりません（copilot.lua / copilot.vim のセットアップ確認）"
        end

        local function fetch_quota(sidebar)
          if not sidebar._copilot_quota_updater then
            sidebar._copilot_quota_updater = InternalUser.make_quota_updater({
              mode = "async",
              cooldown_ms = QUOTA_COOLDOWN_MS,
              render = function(line)
                sidebar._copilot_quota_label = line
                rerender(sidebar)
              end,
              get_auth_headers = function()
                local oauth, oauth_err = get_oauth_token()
                if not oauth or oauth == "" then
                  return nil, oauth_err or "OAuthなし"
                end
                return { "Bearer " .. oauth, "token " .. oauth }, nil
              end,
              on_auth_error = function(oauth_err)
                sidebar._copilot_quota_label = "Premium: 取得失敗（" .. (oauth_err or "OAuthなし") .. "）"
                rerender(sidebar)
              end,
              on_error = function(err)
                if err and err.kind == "http" then
                  sidebar._copilot_quota_label = "Premium: 取得失敗（HTTP " .. tostring(err.status) .. "）"
                  rerender(sidebar)
                end
              end,
              fetch_opts = function()
                local provider_conf = Providers.get_config("copilot")
                return {
                  user_agent = "Avante.nvim",
                  timeout = provider_conf.timeout,
                  proxy = provider_conf.proxy,
                  insecure = provider_conf.allow_insecure,
                }
              end,
              format = function(json)
                return InternalUser.format_premium_label(json, { prefix = "Premium", show_reset = false })
              end,
            })
          end

          if not sidebar._copilot_quota_label then
            sidebar._copilot_quota_label = "Premium: 取得中…"
            rerender(sidebar)
          end

          local updater = sidebar._copilot_quota_updater
          if type(updater) == "function" then
            updater()
          end
        end

        -- Wrap result header rendering to include quota label next to the model name.
        do
          local original_render_header = Sidebar.render_header
          Sidebar.render_header = function(self, winid, bufnr, header_text, hl, reverse_hl, opts)
            local provider = Config.provider
            local result_winid = self.containers.result and self.containers.result.winid
            local quota_label = self._copilot_quota_label

            local model_backup = nil
            if
              provider == "copilot"
              and quota_label
              and winid == result_winid
              and opts
              and opts.include_model
              and Config.windows.sidebar_header.include_model
            then
              local conf = Config.providers and Config.providers[provider] or nil
              if conf and type(conf.model) == "string" then
                model_backup = conf.model
                conf.model = model_backup .. " | " .. quota_label
              end
            end

            local ok, ret = pcall(original_render_header, self, winid, bufnr, header_text, hl, reverse_hl, opts)
            if model_backup then
              Config.providers[provider].model = model_backup
            end
            if ok then
              return ret
            end
            error(ret)
          end
        end

        -- Trigger quota fetch whenever the result view is rendered (rate-limited).
        local original_render_result = Sidebar.render_result
        Sidebar.render_result = function(self)
          if Config.provider == "copilot" then
            fetch_quota(self)
          end
          return original_render_result(self)
        end
      end
    end,
  },
}
