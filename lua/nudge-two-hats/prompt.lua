-- prompt.lua
-- プロンプト生成のための機能

local M = {}

-- プロンプトを生成する関数
-- @param role - ロール（役割）
-- @param selected_hat - 選択された帽子
-- @param direction - 方向性や指示
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
-- @param message_length - 通知メッセージの最大文字数
function M.generate_prompt(role, selected_hat, direction, emotion, tone, prompt_text, message_length)
    -- ヒアドキュメント構文を使用して、複数行のプロンプトを作成
    local base = [[
I am a %s wearing the %s hat.
%s.
With %s emotions and a %s tone, I will advise:
%s

IMPORTANT: 必ずレスポンスは%d文字以内にしてください。長すぎるレスポンスは切り捨てられます。]]

    -- フォーマットを適用
    return string.format(base, role, selected_hat, direction, emotion, tone, prompt_text, message_length)
end

-- 帽子がない場合のプロンプトを生成する関数
-- @param role - ロール（役割）
-- @param direction - 方向性や指示
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
-- @param message_length - 仮想テキストメッセージの最大文字数
function M.generate_prompt_without_hat(role, direction, emotion, tone, prompt_text, message_length)
    -- ヒアドキュメント構文を使用して、複数行のプロンプトを作成
    local base = [[
I am a %s.
%s.
With %s emotions and a %s tone, I will advise:
%s

IMPORTANT: Your response MUST be concise and not exceed %d characters. Longer responses will be truncated.]]

    -- フォーマットを適用
    return string.format(base, role, direction, emotion, tone, prompt_text, message_length)
end

return M
