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

-- 極端に厳格なメッセージ多様性確保関数
function M.ensure_variety(new_message)
  -- 直近のメッセージと重複していないか確認
  for _, old_message in ipairs(message_history) do
    local similarity = calculate_similarity(new_message, old_message)
    if similarity > 0.4 then  -- 40%以上類似していたら拒否（より厳格に）
      return false
    end
  end
  
  -- 極端に短いメッセージや長すぎるメッセージの連続を防ぐ
  if #message_history > 0 then
    local last_length = #message_history[1]
    local current_length = #new_message
    
    -- 前回と同じような長さの連続を避ける
    local length_ratio = math.abs(current_length - last_length) / math.max(current_length, last_length, 1)
    if length_ratio < 0.3 then  -- 30%未満の長さ変化は類似とみなす
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

-- 適度なバリエーションを持つコンテキスト指示生成
local function generate_contextual_instruction(context)
  local instructions = {}
  
  -- 時間帯による適度なアプローチの変化
  local hour_approaches = {
    [0] = "深夜の静けさを活かした集中的な観点で",
    [1] = "夜更けの冷静な判断力を使って",
    [2] = "未明の新鮮な発想で",
    [3] = "夜明け前の清澄な思考で",
    [4] = "早朝の研ぎ澄まされた集中力で",
    [5] = "朝の活力ある視点で",
    [6] = "朝の希望に満ちた前向きな姿勢で",
    [7] = "朝の計画的なアプローチで",
    [8] = "午前の効率的な作業観点から",
    [9] = "朝の戦略的思考で",
    [10] = "午前の体系的なアプローチで",
    [11] = "午前中の建設的な視点で",
    [12] = "正午の明確で直接的な観点で",
    [13] = "午後の柔軟な思考で",
    [14] = "午後の分析的なアプローチで",
    [15] = "夕方の創造的な視点で",
    [16] = "夕方の総合的な判断で",
    [17] = "夕方の振り返りを活かした視点で",
    [18] = "夜の始まりの落ち着いた観点で",
    [19] = "夜の深い思考で",
    [20] = "夜の知的な探求心で",
    [21] = "夜の洞察力を活かして",
    [22] = "夜更けの客観的な視点で",
    [23] = "深夜の静寂な思考で"
  }
  
  local hour_instruction = hour_approaches[context.hour] or "バランスの取れた観点で"
  table.insert(instructions, hour_instruction)
  
  -- ファイルタイプ別の実用的な専門指示
  local file_specific = {
    lua = "Luaの簡潔さと柔軟性を重視した",
    py = "Pythonの可読性とエレガンスを活かした",
    js = "JavaScriptの非同期処理とモジュール性を考慮した",
    md = "Markdownの文書構造と可読性を重視した",
    markdown = "文章の論理性と情報整理を重視した",
    json = "データ構造の明確性と検証しやすさを考えた",
    yaml = "設定の可読性と保守性を重視した",
    html = "セマンティクスとアクセシビリティを考慮した",
    css = "レスポンシブ性と保守性を重視した",
    rs = "メモリ安全性とパフォーマンスを重視した",
    go = "並行処理とシンプルさを活かした",
    java = "オブジェクト指向設計と保守性を重視した",
    c = "パフォーマンスと効率性を重視した",
    cpp = "オブジェクト指向とシステムレベルの最適化を考えた",
    sh = "スクリプトの堅牢性と可読性を重視した",
    sql = "データの整合性とクエリ効率を重視した",
    text = "文章の明確さと内容の精度を重視した",
    txt = "テキストの構造化と可読性を重視した",
    changelog = "変更履歴の詳細性と時系列の明確さを重視した",
    log = "ログの構造化と追跡可能性を重視した"
  }
  
  if file_specific[context.file_type] then
    table.insert(instructions, file_specific[context.file_type])
  end
  
  -- 作業パターン別の実用的な指示
  local work_pattern_approaches = {
    function_definition = "関数設計の明確性と再利用性を重視した",
    variable_declaration = "変数名の意図明確性とスコープ管理を考慮した",
    commenting = "コードの意図と将来の保守性を重視した",
    general_editing = "コード品質と可読性の向上を目指した"
  }
  
  local pattern_instruction = work_pattern_approaches[context.work_pattern] or work_pattern_approaches.general_editing
  table.insert(instructions, pattern_instruction)
  
  -- 進捗率による適度な視点の変化
  local progress_perspectives = {
    [0.0] = "初期段階での基盤構築を重視した",
    [0.1] = "開始フェーズでの方向性確立を意識した",
    [0.2] = "序盤での構造設計を重視した",
    [0.3] = "基盤部分の安定性を重視した",
    [0.4] = "中間段階での一貫性を考慮した",
    [0.5] = "中盤での効率性と品質バランスを重視した",
    [0.6] = "後半に向けた統合性を考慮した",
    [0.7] = "完成度向上を重視した",
    [0.8] = "最終段階での品質確保を重視した",
    [0.9] = "完成に向けた最終調整を意識した",
    [1.0] = "完成形態での最適化を重視した"
  }
  
  local progress_key = math.floor(context.progress_ratio * 10) / 10
  local progress_instruction = progress_perspectives[progress_key] or "バランスの取れた開発観点で"
  table.insert(instructions, progress_instruction)
  
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
  
  -- 実用的で多様なアプローチ指示
  local practical_approaches = {
    "経験豊富な開発者として、保守性と効率性を重視した",
    "コードレビューアとして、品質向上の観点から",
    "システム設計者として、拡張性と安定性を考慮した",
    "プロジェクトリーダーとして、チーム開発での可読性を重視した",
    "パフォーマンス専門家として、実行効率の最適化を重視した",
    "セキュリティエンジニアとして、安全性と堅牢性を考慮した",
    "テスト専門家として、テスタビリティと検証可能性を重視した",
    "アーキテクトとして、設計パターンと構造の美しさを重視した",
    "メンテナンスエンジニアとして、将来の変更への対応を考慮した",
    "ドキュメンテーション専門家として、理解しやすさを重視した",
    "ユーザビリティ専門家として、使いやすさと直感性を重視した",
    "品質保証エンジニアとして、信頼性と安定性を重視した",
    "DevOpsエンジニアとして、運用性とデプロイ効率を考慮した",
    "技術コンサルタントとして、ベストプラクティスの適用を重視した",
    "新人指導者として、学習しやすさと理解しやすさを考慮した",
    "リファクタリング専門家として、コードの改善と最適化を重視した"
  }
  
  -- 極端に複雑な乱数シード（複数要素のカオス的組み合わせ）
  local chaos_seed = os.time() + 
    (context.current_line * 23) + 
    (#message_history * 47) + 
    (context.hour * 71) + 
    (context.cursor_column * 13) + 
    (#context.current_line_content * 31) +
    (context.total_lines * 11) +
    (string.byte((context.file_type and context.file_type ~= "") and context.file_type or "txt", 1) * 19)
  
  math.randomseed(chaos_seed)
  local practical_approach = practical_approaches[math.random(#practical_approaches)]
  
  -- 適度な視点の多様化要素
  local perspective_modifiers = {
    "実用性を重視した",
    "効率性を考慮した",
    "保守性を重視した",
    "可読性を重視した",
    "安定性を考慮した",
    "拡張性を重視した",
    "品質を重視した",
    "バランスの取れた",
    "体系的な",
    "論理的な",
    "構造化された",
    "最適化された"
  }
  
  local perspective_modifier = perspective_modifiers[math.random(#perspective_modifiers)]
  
  -- 実用的で多様性のあるプロンプト強化
  local enhanced_prompt = prompt_text .. "\n\n" .. base_context .. "\n\n" ..
    "アドバイス指示: " .. perspective_modifier .. contextual_instruction .. "、" .. practical_approach .. "観点でアドバイスしてください。" ..
    pattern_avoidance
  
  -- 履歴がある場合の多様性確保指示
  if #message_history > 0 then
    enhanced_prompt = enhanced_prompt .. "\n\n多様性確保: 以下の点で前回までのメッセージと異なる視点を提供してください:" ..
      "\n- 表現スタイルと語調の変化" ..
      "\n- アプローチ方法と解決手順の多様化" ..
      "\n- 重視する観点と評価基準の変更" ..
      "\n- 説明の構造と情報の優先順位の調整"
    
    -- 直近3つのメッセージを参考として提示
    for i = 1, math.min(3, #message_history) do
      enhanced_prompt = enhanced_prompt .. "\n\n参考メッセージ #" .. i .. " (異なる視点で): \"" .. (message_history[i] or "") .. "\""
    end
    
    -- 建設的な差別化指示
    enhanced_prompt = enhanced_prompt .. "\n\n品質重視: 前回と異なる有用な視点を提供し、実用的で価値あるアドバイスを心がけてください。"
  end
  
  return enhanced_prompt
end

-- デバッグ用：現在のコンテキスト情報を取得
function M.get_current_context()
  return last_context_info
end

return M
