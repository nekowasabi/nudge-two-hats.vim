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
-- @param context - The context of the prompt (e.g., "notification", "virtual_text")
-- @param last_message_to_avoid - (Optional) Previous message to avoid repeating
function M.generate_prompt(role, selected_hat, direction, emotion, tone, prompt_text, message_length, context, last_message_to_avoid)
    local advisory_line
    if context == "notification" then
        advisory_line = string.format("As a UI notification, with %s emotions and a %s tone, I will advise:", emotion, tone)
    elseif context == "virtual_text" then
        advisory_line = string.format("For subtle virtual text display, with %s emotions and a %s tone, I will advise:", emotion, tone)
    else
        advisory_line = string.format("With %s emotions and a %s tone, I will advise:", emotion, tone) -- Fallback
    end

    local base = [[
I am a %s wearing the %s hat.
%s.
%s
%s

IMPORTANT: 必ずレスポンスは%d文字以内にしてください。長すぎるレスポンスは切り捨てられます。]]
    
    local final_prompt = string.format(base, role, selected_hat, direction, advisory_line, prompt_text, message_length)

    if last_message_to_avoid and last_message_to_avoid ~= "" then
        local lua_literal_message = string.format("%q", last_message_to_avoid)
        final_prompt = final_prompt .. '\n\nCRITICAL INSTRUCTION: Your response MUST NOT be identical or very similar to the following previous message: ' .. lua_literal_message .. '. Generate a distinct new message.'
    end
    
    return final_prompt
end

-- 帽子がない場合のプロンプトを生成する関数
-- @param role - ロール（役割）
-- @param direction - 方向性や指示
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
-- @param message_length - 仮想テキストメッセージの最大文字数
-- @param context - The context of the prompt (e.g., "notification", "virtual_text")
-- @param last_message_to_avoid - (Optional) Previous message to avoid repeating
function M.generate_prompt_without_hat(role, direction, emotion, tone, prompt_text, message_length, context, last_message_to_avoid)
    local advisory_line
    if context == "notification" then
        advisory_line = string.format("As a UI notification, with %s emotions and a %s tone, I will advise:", emotion, tone)
    elseif context == "virtual_text" then
        advisory_line = string.format("For subtle virtual text display, with %s emotions and a %s tone, I will advise:", emotion, tone)
    else
        advisory_line = string.format("With %s emotions and a %s tone, I will advise:", emotion, tone) -- Fallback
    end

    local base = [[
I am a %s.
%s.
%s
%s

IMPORTANT: Your response MUST be concise and not exceed %d characters. Longer responses will be truncated.]]

    local final_prompt = string.format(base, role, direction, advisory_line, prompt_text, message_length)

    if last_message_to_avoid and last_message_to_avoid ~= "" then
        local lua_literal_message = string.format("%q", last_message_to_avoid)
        final_prompt = final_prompt .. '\n\nCRITICAL INSTRUCTION: Your response MUST NOT be identical or very similar to the following previous message: ' .. lua_literal_message .. '. Generate a distinct new message.'
    end
    
    return final_prompt
end

return M
