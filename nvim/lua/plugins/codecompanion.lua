local function snacks_slash()
  return { opts = { provider = "snacks" } }
end

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "zbirenbaum/copilot.lua",
    },
    cmd = {
      "CodeCompanion",
      "CodeCompanionActions",
      "CodeCompanionChat",
      "CodeCompanionCmd",
    },
    keys = {
      { "<leader>ccm", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "AI Actions" },
      { "<C-;>", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v", "i" }, desc = "AI Chat Toggle" },
      { "<leader>cca", "<cmd>CodeCompanionChat Add<cr>", mode = { "n", "v" }, desc = "Add to AI Chat" },
    },
    opts = {
      language = "Japanese",
      log_level = "DEBUG", -- Enable debug logging to troubleshoot issues
      adapters = {
        http = {
          copilot = function()
            local adapter = require("codecompanion.adapters").extend("copilot", {
              schema = {
                model = {
                  -- default = "claude-sonnet-4.5",
                  default = "gpt-5-mini",
                },
              },
            })

            -- Work around intermittent schema validation errors when Copilot model choices
            -- haven't been cached yet (choices() can return nil in async mode).
            do
              local original_choices = adapter.schema and adapter.schema.model and adapter.schema.model.choices
              if type(original_choices) == "function" then
                adapter.schema.model.choices = function(self, opts)
                  if opts == nil then
                    opts = { async = false }
                  end
                  return original_choices(self, opts)
                end
              end
            end

            return adapter
          end,
        },
      },
      strategies = {
        chat = {
          adapter = "copilot",
          opts = {
            system_prompt = function(ctx)
              return ctx.default_system_prompt
                .. "\n\n"
                .. "重要: 非コードの回答は必ず自然な日本語で行ってください。"
                .. " 英語で返さず、見出し・本文・箇条書き・補足もすべて日本語にしてください。"
            end,
          },
          roles = {
            llm = function(adapter)
              return "CodeCompanion (" .. adapter.formatted_name .. ")"
            end,
            user = "Me",
          },
          slash_commands = {
            ["buffer"] = snacks_slash(),
            ["file"] = snacks_slash(),
            ["help"] = snacks_slash(),
            ["symbols"] = snacks_slash(),
          },
        },
        inline = {
          adapter = "copilot",
        },
      },
      display = {
        action_palette = {
          provider = "snacks",
        },
        chat = {
          auto_scroll = true,
          show_header_separator = true,
          show_settings = true,
          show_token_count = false,
          window = {
            layout = "float",
            width = 0.9,
            height = 0.9,
            border = "rounded",
            relative = "editor",
          },
        },
      },
    },
    init = function()
      vim.cmd([[cab cc CodeCompanion]])

      vim.api.nvim_create_user_command("CodeCompanionCopilotStats", function()
        local ok_stats, stats = pcall(require, "codecompanion.adapters.http.copilot.stats")
        if not ok_stats or not stats or not stats.show then
          return vim.notify("Copilot stats are not available", vim.log.levels.WARN)
        end
        return stats.show()
      end, { desc = "Show Copilot usage/quota statistics" })

      vim.keymap.set("n", "<leader>ccs", "<cmd>CodeCompanionCopilotStats<cr>", { desc = "Copilot Stats" })

      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatCreated",
        callback = function(args)
          local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
          if not chat then
            return
          end

          local is_copilot = chat.adapter and chat.adapter.name == "copilot"
          local ok_token, token = pcall(require, "codecompanion.adapters.http.copilot.token")
          local ok_cfg, cfg = pcall(require, "codecompanion.config")
          local ok_internal, InternalUser = pcall(require, "copilot_internal_user")

          local ns_generating = vim.api.nvim_create_namespace("codecompanion-generating")
          local generating_mark = nil
          local generating_seq = 0

          local function render_quota(line)
            local winnr = chat.ui and chat.ui.winnr
            if winnr and vim.api.nvim_win_is_valid(winnr) then
              vim.api.nvim_set_option_value("winbar", "%#Comment# " .. line .. " %*", { win = winnr })
            end
          end

          local quota_updater = nil
          if is_copilot and ok_token and ok_internal and ok_cfg then
            quota_updater = InternalUser.make_quota_updater({
              mode = "sync",
              cooldown_ms = 5000,
              render = render_quota,
              get_auth_headers = function()
                local fetched = token.fetch({ force = true }) or {}
                local oauth = fetched.oauth_token
                if not oauth or oauth == "" then
                  return nil, "no_oauth"
                end
                return { "Bearer " .. oauth }, nil
              end,
              on_auth_error = function()
                render_quota("Copilot Premium: 取得失敗（認証トークンなし）")
              end,
              on_error = function(err)
                if err and err.kind == "json" then
                  return render_quota("Copilot Premium: 取得失敗（JSON）")
                end
                return render_quota("Copilot Premium: 取得失敗")
              end,
              fetch_opts = function()
                return {
                  user_agent = "CodeCompanion.nvim",
                  insecure = cfg.adapters.http.opts.allow_insecure,
                  proxy = cfg.adapters.http.opts.proxy,
                  check_status = false,
                }
              end,
              format = function(json)
                return InternalUser.format_premium_label(json, { prefix = "Copilot Premium", show_reset = true })
                  or "Copilot Premium: （情報なし）"
              end,
            })
          end

          local function clear_generating()
            generating_seq = generating_seq + 1
            if generating_mark then
              pcall(vim.api.nvim_buf_del_extmark, chat.bufnr, ns_generating, generating_mark)
              generating_mark = nil
            end
          end

          chat:add_callback("on_submitted", function()
            clear_generating()
            local my_seq = generating_seq + 1
            generating_seq = my_seq

            local function render_at_bottom()
              if my_seq ~= generating_seq then
                return
              end
              if not vim.api.nvim_buf_is_valid(chat.bufnr) then
                return
              end

              local lc = vim.api.nvim_buf_line_count(chat.bufnr)
              local row = math.max(lc - 1, 0)
              generating_mark = vim.api.nvim_buf_set_extmark(chat.bufnr, ns_generating, row, 0, {
                id = generating_mark,
                strict = false,
                virt_lines = {
                  { { "" } },
                  { { " generating…", "Comment" } },
                },
                virt_lines_above = false,
                priority = 120,
              })
              vim.defer_fn(render_at_bottom, 120)
            end

            render_at_bottom()
          end)

          chat:add_callback("on_completed", clear_generating)
          chat:add_callback("on_cancelled", clear_generating)
          chat:add_callback("on_ready", clear_generating)

          chat:add_callback("on_completed", function()
            if quota_updater then
              vim.schedule(quota_updater)
            end
          end)

          if is_copilot and quota_updater then
            render_quota("Copilot Premium: 取得中…")
            vim.schedule(quota_updater)

            vim.api.nvim_create_autocmd("User", {
              group = chat.aug,
              pattern = "CodeCompanionChatOpened",
              callback = function(ev)
                if not ev.data or ev.data.bufnr ~= chat.bufnr then
                  return
                end
                render_quota("Copilot Premium: 取得中…")
                vim.schedule(quota_updater)
              end,
            })
          end
        end,
      })
    end,
  },
}
