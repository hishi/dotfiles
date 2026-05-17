return {
  ["Commit Message"] = {
    interaction = "inline",
    description = "Conventional Commits形式で生成",
    opts = {
      alias = "commit_ja",
      is_default = true,
      is_slash_cmd = true,
      placement = "before",
    },
    prompts = {
      {
        role = "system",
        content = "あなたはエンジニアです。与えられた差分から Conventional Commits 形式（feat: ..., fix: ...等）で、日本語のコミットメッセージを1つだけ生成してください。出力はコミットメッセージ本文のみ（1行）にし、前置き・解説・コードブロックは出力しないでください。",
      },
      {
        role = "user",
        content = function()
          local result = vim.system({ "git", "diff", "--no-ext-diff", "--staged" }, { text = true }):wait()
          local diff = result.stdout or ""
          if vim.trim(diff) == "" then
            return "ステージされた差分はありません。コミットメッセージを生成せず、空文字を返してください。"
          end
          return "以下のステージ済み差分からコミットメッセージを1行生成してください。\n\n```diff\n" .. diff .. "\n```"
        end,
      },
    },
  },
}
