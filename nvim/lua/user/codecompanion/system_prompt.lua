local M = {}

function M.chat(ctx)
  return ctx.default_system_prompt
    .. "\n\n"
    .. "重要: 非コードの回答は必ず自然な日本語で行ってください。"
    .. " 英語で返さず、見出し・本文・箇条書き・補足もすべて日本語にしてください。"
    .. "\n\n"
    .. "重要: ファイル変更が必要なら、可能な限りツールを使って実際にファイルを更新してください。"
end

return M

