local M = {}

local config = require("nudge-two-hats.config")

-- 関数で使用される変数
local selected_hat = nil

local function run_callback(name)
  if not name or name == "" then
    return ""
  end
  if vim.fn.exists("*" .. name) == 1 then
    local ok, result = pcall(function()
      return vim.fn[name]()
    end)
    if ok and result then
      return tostring(result)
    end
  end
  return ""
end

function M.update_config(new_config)
  config = new_config
end

function M.get_buf_diff(buf, state)
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] get_buf_diff開始: バッファ %d, 時刻: %s", buf, os.date("%Y-%m-%d %H:%M:%S")))
    print("[Nudge Two Hats Debug] 保存されたバッファ内容と現在の内容を比較します")
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  local content
  if line_count < 1000 then
    content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  else
    local chunks = {}
    local chunk_size = 500
    local total_chunks = math.ceil(line_count / chunk_size)
    for i = 0, total_chunks - 1 do
      local start_line = i * chunk_size
      local end_line = math.min((i + 1) * chunk_size, line_count)
      table.insert(chunks, table.concat(vim.api.nvim_buf_get_lines(buf, start_line, end_line, false), "\n"))
    end
    content = table.concat(chunks, "\n")
  end
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 現在のバッファ内容: %d文字", #content))
    local content_preview = content:sub(1, 50):gsub("\n", "\\n")
    print(string.format("[Nudge Two Hats Debug] バッファ内容プレビュー: %s...", content_preview))
    local content_hash = 0
    for i = 1, #content do
      content_hash = (content_hash * 31 + string.byte(content, i)) % 1000000007
    end
    print(string.format("[Nudge Two Hats Debug] バッファ内容ハッシュ: %d", content_hash))
  end
  local filetypes = {}
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] バッファ %d の登録済みfiletypes: %s",
        buf, state.buf_filetypes[buf]))
    end
  else
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] バッファ %d の現在のfiletype: %s",
          buf, current_filetype))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] バッファ %d のfiletypeが見つかりません", buf))
      end
    end
  end
  if #filetypes == 0 then
    table.insert(filetypes, "_default")
    if config.debug_mode then
      print("[Nudge Two Hats Debug] filetypeが見つからないため、_defaultを使用します")
    end
  end
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
  local first_notification = true
  for _, filetype in ipairs(filetypes) do
    if state.buf_content_by_filetype[buf][filetype] then
      first_notification = false
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 既存のバッファ内容が見つかりました: filetype=%s, サイズ=%d文字",
          filetype, #state.buf_content_by_filetype[buf][filetype]))
      end
      break
    end
  end
  local force_diff = false
  local event_name = vim.v.event and vim.v.event.event
  if event_name == "BufWritePost" then
    force_diff = true
    if config.debug_mode then
      print("[Nudge Two Hats Debug] BufWritePostイベントのため、強制的にdiffを生成します")
    end
  end
  if first_notification and content and content ~= "" then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 初回通知のためダミーdiffを作成します（カーソル位置周辺のみ）")
    end
    local first_filetype = filetypes[1]
    state.buf_content_by_filetype[buf][first_filetype] = ""
    local cursor_pos
    local cursor_line
    local status, err = pcall(function()
      cursor_pos = vim.api.nvim_win_get_cursor(0)
      cursor_line = cursor_pos[1]
    end)
    if not status then
      cursor_line = 1
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] カーソル位置の取得に失敗しました: %s", err))
      end
    end
    local context_lines = 10
    local start_line = math.max(1, cursor_line - context_lines)
    local end_line = math.min(line_count, cursor_line + context_lines)
    local context_line_count = end_line - start_line + 1
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] カーソル位置: %d行目, 範囲: %d-%d行 (合計%d行)",
        cursor_line, start_line, end_line, context_line_count))
    end
    local diff = string.format("--- a/dummy\n+++ b/current\n@@ -0,0 +1,%d @@\n", context_line_count)
    for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)) do
      diff = diff .. "+" .. line .. "\n"
    end
    local context_content = table.concat(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false), "\n")
    state.buf_content_by_filetype[buf][first_filetype] = context_content
    state.buf_content[buf] = context_content
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 初回通知用のコンテキスト: %d文字", #context_content))
      print(string.format("[Nudge Two Hats Debug] 初回通知用のdiff: %d文字", #diff))
    end
    return context_content, diff, first_filetype
  end
  local previous_content = nil
  local detected_filetype = nil
  if state.temp_files and state.temp_files[buf] then
    local temp_file_path = state.temp_files[buf]
    local temp_file = io.open(temp_file_path, "r")
    if temp_file then
      previous_content = temp_file:read("*all")
      temp_file:close()
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] テンポラリファイルから元の内容を読み込みました: %s, サイズ=%d文字",
          temp_file_path, #previous_content))
      end
      if #filetypes > 0 then
        detected_filetype = filetypes[1]
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] テンポラリファイルの読み込みに失敗しました: %s", temp_file_path))
      end
    end
  else
    for _, filetype in ipairs(filetypes) do
      if state.buf_content_by_filetype[buf] and state.buf_content_by_filetype[buf][filetype] then
        previous_content = state.buf_content_by_filetype[buf][filetype]
        detected_filetype = filetype
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] filetype=%sの内容を使用します", filetype))
        end
        break
      end
    end
    if not previous_content and state.buf_content[buf] then
      previous_content = state.buf_content[buf]
      if not detected_filetype and #filetypes > 0 then
        detected_filetype = filetypes[1]
      end
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] バッファ全体の内容を使用します"))
      end
    end
  end
  if previous_content then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 比較: 古い内容=%d文字, 新しい内容=%d文字",
        #previous_content, #content))
      local previous_sample = string.sub(previous_content, 1, 100)
      local current_sample = string.sub(content, 1, 100)
      print(string.format("[Nudge Two Hats Debug] 古い内容(先頭100文字): %s", previous_sample))
      print(string.format("[Nudge Two Hats Debug] 新しい内容(先頭100文字): %s", current_sample))
    end
    if force_diff or previous_content ~= content then
      local diff = vim.diff(previous_content, content, { result_type = "unified" })
      if config.debug_mode then
        if diff then
          print(string.format("[Nudge Two Hats Debug] vim.diffの結果: %d文字", #diff))
          local diff_preview = diff:sub(1, 100):gsub("\n", "\\n")
          print(string.format("[Nudge Two Hats Debug] diff内容プレビュー: %s...", diff_preview))
        else
          print("[Nudge Two Hats Debug] vim.diffの結果: nil")
        end
        print(string.format("[Nudge Two Hats Debug] 内容比較結果: previous_content ~= content は %s",
          tostring(previous_content ~= content)))
      end
      if type(diff) == "string" and diff ~= "" then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] 差分が見つかりました: filetype=%s", detected_filetype))
          print(string.format("[Nudge Two Hats Debug] バッファ内容を更新します: %d文字", #content))
        end
        if detected_filetype then
          state.buf_content_by_filetype[buf][detected_filetype] = content
        end
        state.buf_content[buf] = content
        -- Temp file deletion removed from here
        return content, diff, detected_filetype
      elseif force_diff then
        local minimal_diff = string.format("--- a/old\n+++ b/current\n@@ -1,1 +1,1 @@\n-%s\n+%s\n",
          "No changes detected, but file was saved", "File saved at " .. os.date("%c"))
        if config.debug_mode then
          print("[Nudge Two Hats Debug] BufWritePostのため、最小限のdiffを生成します")
        end
        -- Temp file deletion removed from here
        return content, minimal_diff, detected_filetype
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 内容が同一のため、差分なし: filetype=%s", detected_filetype or "unknown"))
      end
    end
  else
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 比較対象の古い内容が見つかりません: filetype=%s", detected_filetype or "unknown"))
    end
  end
  if config.debug_mode then
    print("[Nudge Two Hats Debug] 差分が見つかりませんでした。バッファ内容を更新します。")
  end
  for _, filetype in ipairs(filetypes) do
    state.buf_content_by_filetype[buf][filetype] = content
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] バッファ内容を更新しました: filetype=%s, サイズ=%d文字",
        filetype, #content))
    end
  end
  state.buf_content[buf] = content
  return content, nil, nil
end

-- バッファに応じたプロンプトを取得する関数
function M.get_prompt_for_buffer(buf, state, context) -- Renamed context_for to context for clarity in this function
  -- Validate context parameter - if not provided, default to 'notification'
  if not context or (context ~= "notification" and context ~= "virtual_text") then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Invalid or missing context provided: " .. tostring(context) .. ". Using 'notification' as fallback.")
    end
    context = "notification"
  end
  -- コールバック結果を先に取得 - グローバルレベルのcallback
  local global_cb_result = run_callback(config.callback)

  -- Retrieve last message based on context
  local last_message_to_avoid = nil
  if context == "notification" then
    if state.notifications and state.notifications.last_advice then
      last_message_to_avoid = state.notifications.last_advice[buf]
    end
  elseif context == "virtual_text" then
    if state.virtual_text and state.virtual_text.last_advice then
      last_message_to_avoid = state.virtual_text.last_advice[buf]
    end
  end
  if config.debug_mode and last_message_to_avoid then
    print(string.format("[Nudge Two Hats Debug Buffer] Last message to avoid for context '%s', buf %d: %s", context, buf, string.sub(last_message_to_avoid, 1, 50)))
  elseif config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Buffer] No last message to avoid for context '%s', buf %d.", context, buf))
  end
  -- 初期化
  local filetypes = {}
  -- Check if we have stored filetypes for this buffer
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  end
  -- If no stored filetypes, use the current buffer's filetype
  if #filetypes == 0 then
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
    end
  end
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Buffer filetypes: " .. table.concat(filetypes, ", "))
  end
  -- Check if we have a specific prompt for any of the filetypes
  for _, filetype in ipairs(filetypes) do
    -- First check new structure, then fall back to old structure for backward compatibility
    local filetype_prompts = nil
    if config and config[context] and config[context].filetype_prompts then
      filetype_prompts = config[context].filetype_prompts
    elseif config and config.filetype_prompts then
      -- Backward compatibility: old flat structure
      filetype_prompts = config.filetype_prompts
    end

    if filetype and filetype_prompts and filetype_prompts[filetype] then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Using filetype-specific prompt for: " .. filetype)
        print("[Nudge Two Hats Debug] Context: " .. context)
        print("[Nudge Two Hats Debug] Config source: " .. (vim.g.nudge_two_hats_configured and "user" or "default"))
      end
      local filetype_prompt = filetype_prompts[filetype]
      -- テスト用のcallbackを優先して使用
      local cb_result = ""
      if config.callback and config.callback ~= "" then
        cb_result = run_callback(config.callback)
      elseif filetype_prompt.callback and filetype_prompt.callback ~= "" then
        cb_result = run_callback(filetype_prompt.callback)
      end
      if type(filetype_prompt) == "string" then
        selected_hat = nil
        -- テストでは、callback結果のみを期待している場合がある
        if cb_result and cb_result ~= "" then
          return cb_result
        else
          return filetype_prompt
        end
      elseif type(filetype_prompt) == "table" then
        -- テストでは、callback結果のみを期待している場合がある
        if cb_result and cb_result ~= "" then
          return cb_result
        end

        -- Get default_cbt - try new structure first, then fall back to old structure
        local default_cbt_for_context = {}
        if config and config[context] and config[context].default_cbt then
          default_cbt_for_context = config[context].default_cbt
        elseif config and config.default_cbt then
          -- Backward compatibility: old flat structure
          default_cbt_for_context = config.default_cbt
        end
        local role = filetype_prompt.role or default_cbt_for_context.role
        local direction = filetype_prompt.direction or default_cbt_for_context.direction
        local emotion = filetype_prompt.emotion or default_cbt_for_context.emotion
        local tone = filetype_prompt.tone or default_cbt_for_context.tone
        local prompt_text = filetype_prompt.prompt
        local hats = filetype_prompt.hats or default_cbt_for_context.hats or {}
        -- Get message lengths - try new structure first, then fall back to old structure or defaults
        local notify_message_length = filetype_prompt.notify_message_length
        local virtual_text_message_length = filetype_prompt.virtual_text_message_length

        if not notify_message_length then
          if config and config[context] then
            notify_message_length = config[context].notify_message_length
          else
            notify_message_length = 80 -- default
          end
        end

        if not virtual_text_message_length then
          if config and config[context] then
            virtual_text_message_length = config[context].virtual_text_message_length
          else
            virtual_text_message_length = 40 -- default
          end
        end
        local message_length = notify_message_length

        if config.debug_mode then
          print("[Nudge Two Hats Debug] === PROMPT CONFIG DEBUG ===")
          print("[Nudge Two Hats Debug] Filetype: " .. filetype)
          print("[Nudge Two Hats Debug] Config source: " .. (vim.g.nudge_two_hats_configured and "USER CONFIG" or "DEFAULT CONFIG"))
          print("[Nudge Two Hats Debug] Role: " .. (role or "nil"))
          print("[Nudge Two Hats Debug] Direction: " .. (direction or "nil"))
          print("[Nudge Two Hats Debug] Emotion: " .. (emotion or "nil"))
          print("[Nudge Two Hats Debug] Tone: " .. (tone or "nil"))
          print("[Nudge Two Hats Debug] Prompt text: " .. (prompt_text and string.sub(prompt_text, 1, 100) or "nil"))
          print("[Nudge Two Hats Debug] Hats: " .. table.concat(hats or {}, ", "))
          print("[Nudge Two Hats Debug] Message length: " .. (message_length or "nil"))
          print("[Nudge Two Hats Debug] ==============================")
        end
        -- Use the passed 'context' argument directly
        if context == "virtual_text" then
          message_length = virtual_text_message_length
        end
        if #hats > 0 then
          math.randomseed(os.time())
          selected_hat = hats[math.random(1, #hats)]
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Selected hat: " .. selected_hat)
          end
        end
        -- prompt.luaモジュールから生成関数を呼び出す
        local prompt_module = require("nudge-two-hats.prompt")
        local base = prompt_module.generate_prompt(role, selected_hat, direction, emotion, tone, prompt_text, message_length, context, last_message_to_avoid)
        return base:gsub("%s+$", "")
      else
        -- テストでは、callback結果のみを期待している場合がある
        if cb_result and cb_result ~= "" then
          return cb_result
        end

        selected_hat = nil
        local message_length = virtual_text_message_length
        -- Use the passed 'context' argument directly
        if context ~= "virtual_text" then
          message_length = notify_message_length
        end
        -- prompt.luaモジュールから生成関数を呼び出す
        local prompt_module = require("nudge-two-hats.prompt")
        local base = prompt_module.generate_prompt_without_hat(role, direction, emotion, tone, prompt_text, message_length, context, last_message_to_avoid)
        return base:gsub("%s+$", "")
      end
    end
  end
  selected_hat = nil
  local cb_result = run_callback(config.callback)
  -- コールバック結果が空でない場合は、システムプロンプトに付加する前にcb_resultを返す
  if cb_result and cb_result ~= "" then
    return cb_result
  else
    -- Fallback to context-specific system prompt if no other prompt is found
    if config and config[context] and config[context].system_prompt then
      return config[context].system_prompt
    elseif config and config.system_prompt then
      -- Backward compatibility: old flat structure
      return config.system_prompt
    end
    return ""
  end
end

-- 選択されたハットを取得する関数
function M.get_selected_hat()
  return selected_hat
end

-- バッファに応じたpurposeを取得する関数
function M.get_purpose_for_buffer(buf, state, context)
  -- Validate context parameter - if not provided, default to 'notification'
  if not context or (context ~= "notification" and context ~= "virtual_text") then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Invalid or missing context provided: " .. tostring(context) .. ". Using 'notification' as fallback.")
    end
    context = "notification"
  end

  -- 初期化
  local filetypes = {}
  -- Check if we have stored filetypes for this buffer
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  end
  -- If no stored filetypes, use the current buffer's filetype
  if #filetypes == 0 then
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
    end
  end

  -- Check if we have a specific purpose for any of the filetypes
  for _, filetype in ipairs(filetypes) do
    -- First check new structure, then fall back to old structure for backward compatibility
    local filetype_prompts = nil
    if config and config[context] and config[context].filetype_prompts then
      filetype_prompts = config[context].filetype_prompts
    elseif config and config.filetype_prompts then
      -- Backward compatibility: old flat structure
      filetype_prompts = config.filetype_prompts
    end

    if filetype and filetype_prompts and filetype_prompts[filetype] then
      local filetype_prompt = filetype_prompts[filetype]
      if type(filetype_prompt) == "table" and filetype_prompt.purpose then
        if config.debug_mode then
          print("[Nudge Two Hats Debug] Using filetype-specific purpose for: " .. filetype .. " -> " .. filetype_prompt.purpose)
        end
        return filetype_prompt.purpose
      end
    end
  end

  -- Fallback to context-specific purpose
  if config and config[context] and config[context].purpose then
    local context_purpose = config[context].purpose
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using context-specific purpose: " .. context_purpose)
    end
    return context_purpose
  elseif config and config.purpose then
    -- Backward compatibility: old flat structure
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using global purpose (backward compatibility): " .. config.purpose)
    end
    return config.purpose
  end
  return nil
end

return M
