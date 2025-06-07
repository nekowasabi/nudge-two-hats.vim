-- message_variety.lua
-- AIメッセージの多様性を高めるための機能

local M = {}

-- 過去のメッセージを保存するテーブル
local message_history = {}
local max_history = 5  -- 保存する履歴の数

-- メッセージの多様性を確保する関数
function M.ensure_variety(new_message)
  -- 直近のメッセージと重複していないか確認
  for _, old_message in ipairs(message_history) do
    -- 類似度チェック（簡易版）
    if string.sub(new_message, 1, 20) == string.sub(old_message, 1, 20) then
      return false  -- 類似メッセージあり
    end
  end
  
  return true  -- ユニークなメッセージ
end

-- メッセージを記録する関数
function M.record_message(message)
  if message and message ~= "" then
    table.insert(message_history, 1, message)
    if #message_history > max_history then
      table.remove(message_history, #message_history)
    end
  end
end

-- 過去のメッセージを取得
function M.get_message_history()
  return message_history
end

-- 履歴をクリア
function M.clear_message_history()
  message_history = {}
  return true
end

-- プロンプトに動的要素を追加する関数
function M.enhance_prompt(prompt_text)
  if not prompt_text or prompt_text == "" then
    return prompt_text
  end
  
  -- 時間帯に応じた変化
  local hour = tonumber(os.date("%H"))
  local time_context = ""
  if hour < 12 then
    time_context = "朝の静かな時間に、"
  elseif hour < 18 then
    time_context = "活動的な昼間の時間に、"
  else
    time_context = "夜の内省の時間に、"
  end
  
  -- ランダム要素の追加
  local variety_factors = {
    "具体的な例を交えて",
    "質問形式で考えさせるように",
    "簡潔に要点をまとめて",
    "禅問答のように",
    "物語形式で"
  }
  -- 乱数シードを現在時刻で設定
  math.randomseed(os.time())
  local random_factor = variety_factors[math.random(#variety_factors)]
  
  -- コンテキスト情報を追加
  local file_extension = vim.fn.expand("%:e")
  local file_name = vim.fn.expand("%:t")
  local current_time = os.date("%H:%M")
  
  -- プロンプトに追加
  local enhanced_prompt = prompt_text .. "\n\n" .. 
    "ADDITIONAL CONTEXT: The user is working on a file with extension \"" .. file_extension .. 
    "\" named \"" .. file_name .. "\". The current time is " .. current_time .. ".\n\n" ..
    time_context .. random_factor .. "アドバイスしてください。"
  
  -- 履歴情報を追加（過去の類似回答を避ける）
  if #message_history > 0 then
    enhanced_prompt = enhanced_prompt .. "\n\nCRITICAL INSTRUCTION: Your response MUST be significantly different from all previous responses to maintain variety."
    
    -- 過去の応答パターンの分析情報をAIに提供
    if #message_history >= 3 then
      enhanced_prompt = enhanced_prompt .. "\n\nNOTE: The last few responses have established a pattern. Ensure your new response breaks this pattern in tone and content structure."
    end
  end
  
  return enhanced_prompt
end

return M
