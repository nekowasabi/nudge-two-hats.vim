-- prompt.lua
-- プロンプト生成のための機能

local M = {}

-- メッセージ多様性モジュールをインポート
local variety = require("nudge-two-hats.message_variety")

-- config設定へのアクセス
local config = require("nudge-two-hats.config")

-- プロンプトを生成する関数
-- @param role - 役割
-- @param selected_hat - モード（帽子）
-- @param direction - 方向性
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
-- @param message_length - 通知メッセージの最大文字数
-- @param context - The context of the prompt (e.g., "notification", "virtual_text")
-- @param last_message_to_avoid - (Optional) Previous message to avoid repeating
function M.generate_prompt(role, selected_hat, direction, emotion, tone, prompt_text, message_length, context, last_message_to_avoid)
    -- 動的な要素を追加（message_varietyモジュールを使用）
    prompt_text = variety.enhance_prompt(prompt_text)
    
    -- Determine context-specific descriptions
    local context_name_str
    local context_guidance_str
    if context == "notification" then
        context_name_str = "UI Notification"
        context_guidance_str = "Your advice will be displayed as a UI notification. It needs to be concise, impactful, and easily digestible at a glance."
    elseif context == "virtual_text" then
        context_name_str = "Virtual Text in Editor"
        context_guidance_str = "Your advice will be shown as virtual text alongside the code. It should be subtle, highly relevant to the immediate code context, and very brief."
    else
        context_name_str = "General Context" -- Fallback
        context_guidance_str = "Your advice will be used in a general context."
    end

    local base_template = [[
# AI Agent Instructions

## 1. Persona
- **Role**: %s
- **Mode (Hat)**: %s

## 2. Objective
- **Direction**: %s

## 3. Style
- **Emotion**: %s
- **Tone**: %s

## 4. Output Medium
- **Context**: %s
- **Guidance for this Context**: %s

## 5. Task
%s

## 6. Constraints
- **Message Length**: Your response MUST be EXACTLY %d characters. Adhere strictly to this character limit.
]]

    local final_prompt = string.format(
      base_template,
      role,
      selected_hat,
      direction,
      emotion,
      tone,
      context_name_str,
      context_guidance_str,
      prompt_text,
      message_length
    )

    if last_message_to_avoid and last_message_to_avoid ~= "" then
        local lua_literal_message = string.format("%q", last_message_to_avoid)
        final_prompt = final_prompt .. '\n\nCRITICAL INSTRUCTION: Your response MUST NOT be identical or very similar to the following previous message: ' .. lua_literal_message .. '. Generate a distinct new message.'
    -- 生成されたプロンプトをログに記録（デバッグ用）
    if config and config.debug_mode then
        print("[Nudge Two Hats Debug] Enhanced prompt with variety features (with hat)")
    end
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
    -- 動的な要素を追加（message_varietyモジュールを使用）
    prompt_text = variety.enhance_prompt(prompt_text)
    
    -- Determine context-specific descriptions (shared with M.generate_prompt or re-defined if necessary)
    local context_name_str
    local context_guidance_str
    if context == "notification" then
        context_name_str = "UI Notification"
        context_guidance_str = "Your advice will be displayed as a UI notification. It needs to be concise, impactful, and easily digestible at a glance."
    elseif context == "virtual_text" then
        context_name_str = "Virtual Text in Editor"
        context_guidance_str = "Your advice will be shown as virtual text alongside the code. It should be subtle, highly relevant to the immediate code context, and very brief."
    else
        context_name_str = "General Context" -- Fallback
        context_guidance_str = "Your advice will be used in a general context."
    end

    local base_template_no_hat = [[
# AI Agent Instructions

## 1. Persona
- **Role**: %s

## 2. Objective
- **Direction**: %s

## 3. Style
- **Emotion**: %s
- **Tone**: %s

## 4. Output Medium
- **Context**: %s
- **Guidance for this Context**: %s

## 5. Task
%s

## 6. Constraints
- **Message Length**: Your response MUST be EXACTLY %d characters. Adhere strictly to this character limit.
]]

    local final_prompt = string.format(
      base_template_no_hat,
      role,
      direction,
      emotion,
      tone,
      context_name_str,
      context_guidance_str,
      prompt_text,
      message_length
    )

    if last_message_to_avoid and last_message_to_avoid ~= "" then
        local lua_literal_message = string.format("%q", last_message_to_avoid)
        final_prompt = final_prompt .. '\n\nCRITICAL INSTRUCTION: Your response MUST NOT be identical or very similar to the following previous message: ' .. lua_literal_message .. '. Generate a distinct new message.'
    -- 生成されたプロンプトをログに記録（デバッグ用）
    if config and config.debug_mode then
        print("[Nudge Two Hats Debug] Enhanced prompt with variety features (without hat)")
    end
    end
    return final_prompt
end

-- AIによる応答を履歴に記録する関数
function M.record_message(message)
  -- message_varietyモジュールに履歴を記録
  variety.record_message(message)
end

-- デバッグ用：履歴を取得
function M.get_message_history()
  return variety.get_message_history()
end

-- デバッグ用：履歴をクリア
function M.clear_message_history()
  return variety.clear_message_history()
end

return M
