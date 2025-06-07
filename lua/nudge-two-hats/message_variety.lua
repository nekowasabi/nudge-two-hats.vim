-- message_variety.lua
-- AIメッセージの多様性を高めるための機能

local M = {}

-- 過去のメッセージを保存するテーブル
local message_history = {}
local max_history = 10  -- 保存する履歴の数

-- より詳細なコンテキスト情報を保存
local context_cache = {}
local last_context_info = {}

-- 高度な類似度チェック
local function calculate_similarity(str1, str2)
  if not str1 or not str2 then return 0 end
  
  -- 完全一致チェック
  if str1 == str2 then return 1.0 end
  
  -- 長さの違いが大きい場合は類似度低い
  local len_diff = math.abs(#str1 - #str2)
  if len_diff > math.max(#str1, #str2) * 0.5 then
    return 0
  end
  
  -- キーワードベースの類似度計算
  local words1 = {}
  local words2 = {}
  
  for word in str1:gmatch("%S+") do
    words1[word:lower()] = (words1[word:lower()] or 0) + 1
  end
  
  for word in str2:gmatch("%S+") do
    words2[word:lower()] = (words2[word:lower()] or 0) + 1
  end
  
  local common_words = 0
  local total_words = 0
  
  for word, count1 in pairs(words1) do
    total_words = total_words + count1
    if words2[word] then
      common_words = common_words + math.min(count1, words2[word])
    end
  end
  
  for word, count2 in pairs(words2) do
    if not words1[word] then
      total_words = total_words + count2
    end
  end
  
  return total_words > 0 and (common_words / total_words) or 0
end

-- メッセージの多様性を確保する関数
function M.ensure_variety(new_message)
  -- 直近のメッセージと重複していないか確認
  for _, old_message in ipairs(message_history) do
    local similarity = calculate_similarity(new_message, old_message)
    if similarity > 0.7 then  -- 70%以上類似していたら拒否
      return false
    end
  end
  
  return true  -- ユニークなメッセージ
end

-- メッセージを記録する関数（コンテキスト情報と一緒に）
function M.record_message(message, context_info)
  if message and message ~= "" then
    table.insert(message_history, 1, message)
    
    -- コンテキスト情報も保存
    if context_info then
      context_cache[message] = {
        file_type = context_info.file_type or vim.fn.expand("%:e"),
        time_of_day = tonumber(os.date("%H")),
        day_of_week = os.date("%A"),
        lines_count = vim.fn.line("$"),
        current_line = vim.fn.line("."),
        timestamp = os.time()
      }
    end
    
    if #message_history > max_history then
      local removed = table.remove(message_history, #message_history)
      context_cache[removed] = nil  -- メモリリーク防止
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

-- 現在のコンテキストを詳細に分析
local function analyze_current_context()
  local current_context = {
    file_type = vim.fn.expand("%:e"),
    file_name = vim.fn.expand("%:t"),
    file_path = vim.fn.expand("%:p"),
    current_line = vim.fn.line("."),
    total_lines = vim.fn.line("$"),
    cursor_column = vim.fn.col("."),
    hour = tonumber(os.date("%H")),
    day_of_week = os.date("%A"),
    current_mode = vim.fn.mode(),
    buffer_size = vim.fn.line("$"),
    
    -- 現在行の内容分析
    current_line_content = vim.fn.getline("."),
    
    -- ファイル進捗率
    progress_ratio = vim.fn.line(".") / math.max(vim.fn.line("$"), 1),
    
    -- 作業パターンの分析
    work_pattern = nil
  }
  
  -- 作業パターンの推定
  if current_context.file_type == "lua" then
    if current_context.current_line_content:match("^%s*function") then
      current_context.work_pattern = "function_definition"
    elseif current_context.current_line_content:match("^%s*local") then
      current_context.work_pattern = "variable_declaration"
    elseif current_context.current_line_content:match("^%s*%-%-") then
      current_context.work_pattern = "commenting"
    end
  end
  
  return current_context
end

-- 時間帯とコンテキストに基づく高度なプロンプト生成
local function generate_contextual_instruction(context)
  local instructions = {}
  
  -- 時間帯による指示の変化
  if context.hour >= 6 and context.hour < 12 then
    table.insert(instructions, "朝の集中した時間に適した、新鮮で前向きなアドバイス")
  elseif context.hour >= 12 and context.hour < 18 then
    table.insert(instructions, "活動的な午後の時間に適した、実践的で具体的なアドバイス")
  elseif context.hour >= 18 and context.hour < 22 then
    table.insert(instructions, "夕方の振り返りの時間に適した、洞察に満ちたアドバイス")
  else
    table.insert(instructions, "夜間の深い思考の時間に適した、内省的で哲学的なアドバイス")
  end
  
  -- ファイルタイプによる専門的指示
  local file_specific = {
    lua = "Lua開発者の視点から、関数型プログラミングの原則を活かした",
    py = "Python開発者として、PEP8やPythonic wayを意識した",
    js = "JavaScript開発者として、ES6+の機能や非同期処理を考慮した",
    md = "技術文書作成者として、読みやすさと構造化を重視した",
    json = "データ設計者として、スキーマの整合性と可読性を考慮した",
    yaml = "設定ファイル設計者として、保守性と明確性を重視した"
  }
  
  if file_specific[context.file_type] then
    table.insert(instructions, file_specific[context.file_type])
  end
  
  -- 作業パターンによる指示
  if context.work_pattern == "function_definition" then
    table.insert(instructions, "関数設計の観点から、単一責任原則とテスタビリティを重視した")
  elseif context.work_pattern == "variable_declaration" then
    table.insert(instructions, "データ構造設計の観点から、型安全性と可読性を考慮した")
  elseif context.work_pattern == "commenting" then
    table.insert(instructions, "ドキュメンテーションの観点から、将来の自分や他者への配慮を込めた")
  end
  
  -- 進捗率による指示
  if context.progress_ratio < 0.3 then
    table.insert(instructions, "プロジェクト初期段階での設計思想や全体的なアプローチに焦点を当てた")
  elseif context.progress_ratio > 0.7 then
    table.insert(instructions, "プロジェクト後期段階でのリファクタリングや最適化に焦点を当てた")
  else
    table.insert(instructions, "開発中盤での実装の質とパフォーマンスに焦点を当てた")
  end
  
  return table.concat(instructions, "、")
end

-- 過去のメッセージパターンを分析
local function analyze_message_patterns()
  if #message_history < 2 then return "" end
  
  local pattern_analysis = {}
  
  -- 長さのパターン分析
  local avg_length = 0
  for _, msg in ipairs(message_history) do
    avg_length = avg_length + #msg
  end
  avg_length = avg_length / #message_history
  
  -- よく使われるキーワードの分析
  local keyword_frequency = {}
  for _, msg in ipairs(message_history) do
    for word in msg:gmatch("%S+") do
      local clean_word = word:lower():gsub("[%p%c%s]", "")
      if #clean_word > 2 then
        keyword_frequency[clean_word] = (keyword_frequency[clean_word] or 0) + 1
      end
    end
  end
  
  -- 最も使用頻度の高いキーワードを取得
  local frequent_keywords = {}
  for word, freq in pairs(keyword_frequency) do
    if freq >= 2 then
      table.insert(frequent_keywords, word)
    end
  end
  
  if #frequent_keywords > 0 then
    table.insert(pattern_analysis, "以下のキーワードの使用を避ける: " .. table.concat(frequent_keywords, ", "))
  end
  
  if avg_length > 50 then
    table.insert(pattern_analysis, "前回までのメッセージが長めだったので、今回は簡潔にする")
  else
    table.insert(pattern_analysis, "前回までのメッセージが短めだったので、今回はより詳細にする")
  end
  
  return #pattern_analysis > 0 and ("\n\nパターン回避指示: " .. table.concat(pattern_analysis, "、")) or ""
end

-- プロンプトに動的要素を追加する関数（大幅に強化）
function M.enhance_prompt(prompt_text)
  if not prompt_text or prompt_text == "" then
    return prompt_text
  end
  
  local context = analyze_current_context()
  last_context_info = context  -- デバッグ用に保存
  
  -- 基本的なコンテキスト情報
  local base_context = string.format(
    "DETAILED CONTEXT:\n" ..
    "- File: %s (%s)\n" ..
    "- Position: Line %d/%d (%.1f%% through file)\n" ..
    "- Time: %s on %s\n" ..
    "- Current work pattern: %s\n",
    context.file_name,
    context.file_type,
    context.current_line,
    context.total_lines,
    context.progress_ratio * 100,
    os.date("%H:%M"),
    context.day_of_week,
    context.work_pattern or "general_editing"
  )
  
  -- 高度なコンテキスト指示
  local contextual_instruction = generate_contextual_instruction(context)
  
  -- パターン回避分析
  local pattern_avoidance = analyze_message_patterns()
  
  -- 革新的なアプローチ指示
  local innovation_approaches = {
    "メタファーや比喩を使った創造的な表現で",
    "逆説的な視点から問題を捉えて",
    "異なる職業の専門家になりきって",
    "歴史上の人物の視点を借りて",
    "科学的な原理を日常に応用して",
    "ストーリーテリングの手法を用いて",
    "数学的・論理的思考を日常語で表現して",
    "芸術的感性を技術的問題に適用して",
    "心理学的洞察を開発プロセスに活かして",
    "禅の教えをコーディングの智慧として"
  }
  
  -- より複雑な乱数シード（時間、ファイル、履歴を組み合わせ）
  local seed = os.time() + context.current_line + (#message_history * 17) + (context.hour * 7)
  math.randomseed(seed)
  local innovation_approach = innovation_approaches[math.random(#innovation_approaches)]
  
  -- 最終的な強化プロンプト
  local enhanced_prompt = prompt_text .. "\n\n" .. base_context .. "\n\n" ..
    "INSTRUCTION ENHANCEMENT: " .. contextual_instruction .. "、" .. innovation_approach .. "アドバイスしてください。" ..
    pattern_avoidance
  
  -- 履歴がある場合の強力な差別化指示
  if #message_history > 0 then
    enhanced_prompt = enhanced_prompt .. "\n\nCRITICAL DIFFERENTIATION: Your response MUST be fundamentally different from all previous messages in:" ..
      "\n- Tone and style\n- Approach to the problem\n- Vocabulary and expressions\n- Perspective and viewpoint\n- Structure and format"
    
    -- 直近のメッセージを明示的に避ける指示
    if #message_history >= 1 then
      enhanced_prompt = enhanced_prompt .. "\n\nLast message to AVOID being similar to: \"" .. (message_history[1] or "") .. "\""
    end
  end
  
  return enhanced_prompt
end

-- デバッグ用：現在のコンテキスト情報を取得
function M.get_current_context()
  return last_context_info
end

return M
