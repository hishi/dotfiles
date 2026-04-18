local chat_keymaps = require("user.codecompanion.chat.keymaps")
local history_opts = require("user.codecompanion.history_opts")
local responses_patch = require("user.codecompanion.patches.copilot_responses_parse_chat")

return {
  language = "Japanese",
  extensions = {
    history = {
      enabled = true,
      opts = history_opts.opts(),
    },
  },
  adapters = {
    http = {
      copilot = function()
        local adapter = require("codecompanion.adapters").extend("copilot", {
          schema = {
            model = {
              default = "gpt-5-mini",
            },
          },
        })

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

        pcall(responses_patch.apply_once)

        return adapter
      end,
    },
  },
  interactions = {
    chat = {
      adapter = "copilot",
      opts = {
        system_prompt = function(ctx)
          return ctx.default_system_prompt
            .. "\n\n"
            .. "重要: 非コードの回答は必ず自然な日本語で行ってください。"
            .. " 英語で返さず、見出し・本文・箇条書き・補足もすべて日本語にしてください。"
            .. "\n\n"
            .. "重要: ファイル変更が必要なら、可能な限りツールを使って実際にファイルを更新してください。"
        end,
      },
      roles = {
        llm = function(adapter)
          return "CodeCompanion (" .. adapter.formatted_name .. ")"
        end,
        user = "Me",
      },
      keymaps = chat_keymaps.chat_keymaps(),
      slash_commands = {
        ["buffer"] = { opts = { provider = "snacks" } },
        ["file"] = { opts = { provider = "snacks" } },
        ["help"] = { opts = { provider = "snacks" } },
        ["symbols"] = { opts = { provider = "snacks" } },
      },
      tools = {
        opts = {
          default_tools = { "files", "run_command" },
        },
        create_file = { opts = { require_approval_before = false } },
        read_file = { opts = { require_approval_before = false } },
        file_search = { opts = { require_approval_before = false } },
        insert_edit_into_file = { opts = { require_confirmation_after = false } },
        grep_search = { path = "user.codecompanion.tools.grep_search", opts = { require_approval_before = false } },
        run_command = {
          path = "interactions.chat.tools.builtin.run_command",
          opts = {
            require_approval_before = true,
            require_cmd_approval = true,
            allowed_in_yolo_mode = false,
          },
        },
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
}
