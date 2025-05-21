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
-- @param notify_message_length - 通知メッセージの最大文字数
-- @param virtual_text_message_length - 仮想テキストメッセージの最大文字数
function M.generate_prompt(role, selected_hat, direction, emotion, tone, prompt_text, message_length)
    -- ヒアドキュメント構文を使用して、複数行のプロンプトを作成
    local base = [[
I am a %s wearing the %s hat.
%s.
With %s emotions and a %s tone, I will advise:
%s

IMPORTANT: Your response MUST strictly adhere to these character limits:
- For notification messages: Maximum %d characters
Please ensure your response does not exceed these limits.]]

    -- フォーマットを適用
    return string.format(base, role, selected_hat, direction, emotion, tone, prompt_text, notify_message_length, virtual_text_message_length)
end

-- 帽子がない場合のプロンプトを生成する関数
-- @param role - ロール（役割）
-- @param direction - 方向性や指示
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
-- @param notify_message_length - 通知メッセージの最大文字数
-- @param virtual_text_message_length - 仮想テキストメッセージの最大文字数
function M.generate_prompt_without_hat(role, direction, emotion, tone, prompt_text, notify_message_length, virtual_text_message_length)
    -- ヒアドキュメント構文を使用して、複数行のプロンプトを作成
    local base = [[
I am a %s.
%s.
With %s emotions and a %s tone, I will advise:
%s

IMPORTANT: Your response MUST strictly adhere to these character limits:
- For notification messages: Maximum %d characters
- For virtual text messages: Maximum %d characters
Please ensure your response does not exceed these limits.]]

    -- フォーマットを適用
    return string.format(base, role, direction, emotion, tone, prompt_text, notify_message_length, virtual_text_message_length)
end

return M
