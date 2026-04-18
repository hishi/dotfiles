local M = {}

function M.apply_once()
  if vim.g.__user_codecompanion_responses_parse_chat_patch then
    return
  end

  local ok_utils, adapter_utils = pcall(require, "codecompanion.utils.adapters")
  local ok_responses, responses = pcall(require, "codecompanion.adapters.http.openai_responses")
  if not ok_utils or not ok_responses then
    return
  end

  local original_parse_chat = responses.handlers.response.parse_chat
  if type(original_parse_chat) ~= "function" then
    return
  end

  responses.handlers.response.parse_chat = function(self, data, tools)
    local result = original_parse_chat(self, data, tools)
    if
      not result
      or result.status ~= "success"
      or not result.output
      or (result.output.content and vim.trim(result.output.content) ~= "")
    then
      return result
    end

    if not self or not self.opts or self.opts.stream then
      return result
    end

    local data_mod = type(data) == "table" and data.body or adapter_utils.clean_streamed_data(data)
    local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
    if not ok or type(json) ~= "table" then
      return result
    end

    local function find_text(output)
      if type(output) ~= "table" then
        return nil
      end
      for _, item in ipairs(output) do
        local content = item and item.content
        if type(content) == "table" then
          for _, block in ipairs(content) do
            if type(block) == "table" and type(block.text) == "string" and vim.trim(block.text) ~= "" then
              return vim.trim(block.text)
            end
          end
        end
      end
      return nil
    end

    local text = find_text(json.output) or find_text(json.response and json.response.output)
    if text and text ~= "" then
      result.output.content = text
    end

    return result
  end

  vim.g.__user_codecompanion_responses_parse_chat_patch = true
end

return M

