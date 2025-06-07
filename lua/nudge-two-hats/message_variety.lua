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

-- 極端に多様化された時間帯とコンテキストに基づく高度なプロンプト生成
local function generate_contextual_instruction(context)
  local instructions = {}
  
  -- 極端に多様化した時間帯による指示の変化
  local hour_personas = {
    [0] = "夜更かし魔術師として、闇に隠された秘密の智慧を解き明かす",
    [1] = "深夜の哲学者として、宇宙の真理に迫る思索を巡らせた",
    [2] = "不眠の発明家として、誰も思いつかない革新的発想で",
    [3] = "夜明け前の預言者として、未来を予見する洞察力で",
    [4] = "早朝の修行僧として、静寂の中で研ぎ澄まされた集中力で",
    [5] = "朝の探検家として、未知の領域を開拓する冒険心で",
    [6] = "太陽の使者として、光と希望に満ちた新たな視点で",
    [7] = "朝食の錬金術師として、日常を非凡に変える魔法で",
    [8] = "通勤電車の社会学者として、人間観察から得た洞察で",
    [9] = "朝会議の戦略家として、一日の勝利を決める戦術で",
    [10] = "午前の建築家として、完璧な構造を設計する精密さで",
    [11] = "昼前の料理人として、最高の一皿を創造する情熱で",
    [12] = "正午の太陽神として、全てを照らす圧倒的なエネルギーで",
    [13] = "昼下がりの詩人として、美しい言葉で真実を紡ぎ出す",
    [14] = "午後の科学者として、実験と検証を重ねる探究心で",
    [15] = "夕方の芸術家として、創造性と美的感覚を活かした",
    [16] = "黄昏の思想家として、一日の経験を昇華させる知恵で",
    [17] = "夕焼けの写真家として、瞬間の美を永遠に刻む技術で",
    [18] = "夜の始まりの指揮者として、優雅なハーモニーを奏でる",
    [19] = "夕食の魔法使いとして、食材を変容させる神秘の力で",
    [20] = "夜の図書館員として、知識の海を自在に泳ぐ博識で",
    [21] = "深夜映画館の監督として、ドラマチックな演出で",
    [22] = "夜更けの天文学者として、星座の配置から運命を読み取り",
    [23] = "真夜中の錬金術師として、不可能を可能に変える秘術で"
  }
  
  local hour_instruction = hour_personas[context.hour] or "時空を超越した存在として、この瞬間に最適な超次元的アドバイスを"
  table.insert(instructions, hour_instruction)
  
  -- 極端に個性的なファイルタイプ別専門指示
  local file_specific = {
    lua = "月の魔法を操るLua巫女として、神秘的な関数の召喚術を駆使した",
    py = "巨大蛇を飼いならすPython使いとして、スケールを自在に操る技を用いた",
    js = "時空を駆けるJavaScript忍者として、非同期の奥義と約束の術を極めた",
    md = "言葉の建築家として、読者の心に響く美しき文章の宮殿を建造する",
    json = "データの錬金術師として、情報を黄金に変える究極の変換魔法で",
    yaml = "設定の庭師として、優美で調和のとれたコンフィグの楽園を創造する",
    html = "ウェブの織り手として、ユーザーの魂を捉える美しき仮想世界を紡ぎ",
    css = "スタイルの魔術師として、視覚の魔法で画面に生命を吹き込む",
    rs = "錆びない鋼の鍛冶師として、メモリ安全な最強の武器を鍛造する",
    go = "並行宇宙の設計者として、ゴルーチンで時空を分割統治する",
    java = "仮想機械の皇帝として、一度書けば宇宙のどこでも動く帝国を築く",
    c = "機械語の詩人として、CPUと直接対話する原始的な美しさで",
    cpp = "システムの魔王として、ハードウェアを意のままに操る闇の力で",
    sh = "シェルの呪文詠唱者として、一行で世界を変える古代の言霊を",
    sql = "データベースの探偵として、関係性の迷宮で真実を探り当てる"
  }
  
  if file_specific[context.file_type] then
    table.insert(instructions, file_specific[context.file_type])
  end
  
  -- 極端に劇的な作業パターン別指示
  local work_pattern_personas = {
    function_definition = "神の手を持つ関数創造主として、宇宙の法則を一つの関数に込める壮大な設計を",
    variable_declaration = "記憶の司書として、データの魂を完璧な器に宿らせる儀式的な宣言を",
    commenting = "未来への伝言者として、時を超えて響く智慧の言葉を石版に刻み込む",
    general_editing = "コードの彫刻家として、無形の理想を有形の美に変える芸術的な編集を"
  }
  
  local pattern_instruction = work_pattern_personas[context.work_pattern] or work_pattern_personas.general_editing
  table.insert(instructions, pattern_instruction)
  
  -- 極端に感情的な進捗率による指示
  local progress_emotions = {
    [0.0] = "空白のキャンバスに宇宙を描く創世記的な情熱で",
    [0.1] = "第一歩を踏み出した冒険者の勇気と期待に満ちた",
    [0.2] = "芽吹く若葉のような初々しい成長への願いを込めて",
    [0.3] = "基盤を築く建築家の揺るぎない意志と設計美学で",
    [0.4] = "中間点への道程を歩む旅人の粘り強い探究心で",
    [0.5] = "折り返し地点の戦士として、勝利への確信と戦略眼で",
    [0.6] = "成熟への階段を登る賢者の深遠な洞察力と経験値で",
    [0.7] = "完成に向かう芸術家の繊細な美的感覚と職人技で",
    [0.8] = "仕上げの段階に入った巨匠の完璧主義的なこだわりで",
    [0.9] = "最終章を迎えた作家の壮大な物語完結への想いで",
    [1.0] = "完成の瞬間を迎えた創造神の満足感と達成感に包まれて"
  }
  
  local progress_key = math.floor(context.progress_ratio * 10) / 10
  local progress_instruction = progress_emotions[progress_key] or "未知の進捗率を持つ探検家として、前人未到の領域を切り開く"
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
  
  -- 極端に多様化した革新的アプローチ指示
  local innovation_approaches = {
    "宇宙船の設計エンジニアとして、地球外での開発を想定した視点で",
    "タイムトラベラーとして、100年後の技術者の知見を活かして",
    "料理の鉄人として、コードを食材に見立てた絶妙な調理法で",
    "深海探査隊のリーダーとして、未知の環境での冒険的アプローチで",
    "古代の錬金術師として、神秘的な変換の秘術を用いて",
    "サーカス団長として、観客を魅了するスペクタクルな演出で",
    "忍者の末裔として、見えない技と隠された智慧で",
    "宇宙物理学者として、ブラックホールの謎を解くような洞察で",
    "魔法使いとして、コードに魔法をかけるような神秘的手法で",
    "ジャズミュージシャンとして、即興演奏のような創造的アドリブで",
    "考古学者として、古代文明の叡智を現代技術に蘇らせて",
    "未来の AI として、人間を超越した計算美学の観点から",
    "異次元からの使者として、この世界の常識を超えた視点で",
    "プロファイラーとして、コードの心理的動機を読み解いて",
    "サムライとして、一行一行に武士道の精神を込めて",
    "宇宙の図書館司書として、全知識を統合した究極の整理術で",
    "夢の解釈者として、無意識の欲求をコードに翻訳して",
    "量子コンピューターとして、重ね合わせ状態の複雑思考で",
    "森の賢者として、自然の法則をプログラミングに適用して",
    "時空を操る魔導師として、因果律を超越した解決策で",
    "宇宙海賊として、常識を破る大胆不敵な手法で",
    "パラレルワールドの住人として、この次元では考えられない発想で",
    "ゲームマスターとして、コードを壮大なRPGの舞台として演出し",
    "シャーロック・ホームズとして、細部に隠された真実を推理して",
    "未来の考古学者として、現在のコードを古代遺跡として分析し",
    "宇宙の建築家として、星々を配置するような設計思想で"
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
  local innovation_approach = innovation_approaches[math.random(#innovation_approaches)]
  
  -- 追加の極端な個性化要素
  local extreme_modifiers = {
    "狂気の天才レベルで",
    "宇宙規模の視野から",
    "原子レベルの精密さで",
    "次元を超越した発想で",
    "時間を逆行させるような",
    "重力を無視した自由な",
    "色彩豊かな感性で",
    "音楽的リズムを持って",
    "数学的美しさを追求し",
    "詩的な言葉選びで",
    "革命的な破綻で",
    "予想を裏切る展開で"
  }
  
  local extreme_modifier = extreme_modifiers[math.random(#extreme_modifiers)]
  
  -- 極端に強化されたプロンプト
  local enhanced_prompt = prompt_text .. "\n\n" .. base_context .. "\n\n" ..
    "ULTIMATE INSTRUCTION ENHANCEMENT: " .. extreme_modifier .. contextual_instruction .. "、" .. innovation_approach .. "という" .. extreme_modifier .. "アプローチでアドバイスしてください。" ..
    pattern_avoidance
  
  -- 履歴がある場合の極端に強力な差別化指示
  if #message_history > 0 then
    enhanced_prompt = enhanced_prompt .. "\n\nEXTREME DIFFERENTIATION MANDATE: Your response MUST be radically, dramatically, and fundamentally different from ALL previous messages in:" ..
      "\n- 🎭 Tone and emotional register (if previous was serious, be playful; if gentle, be bold)" ..
      "\n- 🧠 Cognitive approach and problem-solving methodology" ..
      "\n- 📝 Vocabulary, linguistic style, and expression patterns" ..
      "\n- 👁️ Perspective, viewpoint, and philosophical stance" ..
      "\n- 🏗️ Message structure, format, and information architecture" ..
      "\n- 🎨 Creative elements and metaphorical frameworks" ..
      "\n- ⚡ Energy level and intensity of delivery"
    
    -- 直近3つのメッセージを明示的に避ける指示（より徹底的に）
    for i = 1, math.min(3, #message_history) do
      enhanced_prompt = enhanced_prompt .. "\n\nMessage #" .. i .. " to COMPLETELY AVOID: \"" .. (message_history[i] or "") .. "\""
    end
    
    -- 極端な差別化のための追加指示
    enhanced_prompt = enhanced_prompt .. "\n\n🚀 INNOVATION IMPERATIVE: Create something so uniquely different that it feels like it came from a completely different AI personality. Break patterns, exceed expectations, surprise with novelty!"
  end
  
  return enhanced_prompt
end

-- デバッグ用：現在のコンテキスト情報を取得
function M.get_current_context()
  return last_context_info
end

return M
