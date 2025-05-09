local M = {}

local state = {
  enabled = false,
  buf_content = {}, -- Store buffer content for diff calculation (legacy, kept for backward compatibility)
  buf_content_by_filetype = {}, -- Store buffer content by buffer ID and filetype
  buf_filetypes = {}, -- Store buffer filetypes when NudgeTwoHatsStart is executed
  api_key = nil, -- Gemini API key
  last_api_call = 0, -- Timestamp of the last API call
  virtual_text = {
    namespace = nil, -- Namespace for virtual text extmarks
    extmarks = {}, -- Store extmark IDs by buffer
    last_advice = {}, -- Store last advice by buffer
    last_cursor_move = {}, -- Store last cursor move timestamp by buffer
    timers = {}, -- Store virtual text timer IDs by buffer
  }
}

math.randomseed(os.time())

local config = require("nudge-two-hats.config")

local function generate_random_delay()
  local current_delay = config.execution_delay
  local min_value = 60000 -- 最小値は1分（60000ミリ秒）
  local max_value = config.min_interval * 60 * 1000 -- min_intervalを分からミリ秒に変換
  
  local random_factor = 0.7 + math.random() * 0.6 -- 0.7から1.3の間（±30%）
  local new_delay = math.floor(current_delay * random_factor)
  
  new_delay = math.max(new_delay, min_value) -- 最小値の適用
  new_delay = math.min(new_delay, max_value) -- 最大値の適用
  
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 新しいランダム遅延を生成: %dms（元の遅延: %dms、乗数: %.2f）", new_delay, current_delay, random_factor))
  end
  
  return new_delay
end

local translations = {
  en = {
    enabled = "enabled",
    disabled = "disabled",
    api_key_set = "Gemini API key set",
    started_buffer = "Nudge Two Hats started for current buffer",
    debug_enabled = "Debug mode enabled - nudge text will be printed to :messages",
    no_changes = "No changes detected to generate advice",
    api_key_not_set = "Gemini API key not set. Set GEMINI_API_KEY environment variable or use :NudgeTwoHatsSetApiKey to set it.",
    api_error = "Gemini API error",
    unknown_error = "Unknown error",
  },
  ja = {
    enabled = "有効",
    disabled = "無効",
    api_key_set = "Gemini APIキーが設定されました",
    started_buffer = "現在のバッファでNudge Two Hatsが開始されました",
    debug_enabled = "デバッグモードが有効 - ナッジテキストが:messagesに表示されます",
    no_changes = "アドバイスを生成するための変更が検出されませんでした",
    api_key_not_set = "Gemini APIキーが設定されていません。GEMINI_API_KEY環境変数を設定するか、:NudgeTwoHatsSetApiKeyを使用して設定してください。",
    api_error = "Gemini APIエラー",
    unknown_error = "不明なエラー",
  }
}

local function is_japanese(text)
  return text:match("[\227-\233]") ~= nil
end

-- Get the appropriate language for translations
local function get_language()
  if config.output_language == "auto" then
    local lang = vim.fn.getenv("LANG") or ""
    if lang:match("^ja") then
      return "ja"
    else
      return "en"
    end
  else
    return config.output_language
  end
end

-- Safe UTF-8 string truncation that doesn't cut in the middle of a multibyte character
local function safe_truncate(str, max_length)
  if #str <= max_length then
    return str
  end
  
  local chunk_size = 1024 * 1024 -- 1MB chunks
  local result = {}
  local char_count = 0
  local total_processed = 0
  
  while total_processed < #str and char_count < max_length do
    local chunk_end = math.min(total_processed + chunk_size, #str)
    local chunk = string.sub(str, total_processed + 1, chunk_end)
    local bytes = {chunk:byte(1, -1)}
    local i = 1
    
    while i <= #bytes and char_count < max_length do
      local b = bytes[i]
      local width = 1
      
      if b >= 240 and b <= 247 then -- 4-byte sequence
        width = 4
      elseif b >= 224 and b <= 239 then -- 3-byte sequence
        width = 3
      elseif b >= 192 and b <= 223 then -- 2-byte sequence
        width = 2
      end
      
      -- Check if we have a complete sequence and it fits within max_length
      if i + width - 1 <= #bytes then
        for j = 0, width - 1 do
          table.insert(result, bytes[i + j])
        end
        i = i + width
        char_count = char_count + 1
      else
        break
      end
    end
    
    total_processed = chunk_end
  end
  
  local truncated = ""
  for _, b in ipairs(result) do
    truncated = truncated .. string.char(b)
  end
  
  return truncated
end


local function sanitize_text(text)
  if not text then
    return ""
  end
  
  -- Only replace truly invalid UTF-8 sequences
  local sanitized = text:gsub("[\192-\193]", "?") -- Invalid UTF-8 lead bytes
  sanitized = sanitized:gsub("[\245-\255]", "?") -- Invalid UTF-8 lead bytes
  
  local function is_continuation_byte(b)
    return b >= 128 and b <= 191
  end
  
  local chunk_size = 1024 * 1024 -- 1MB chunks
  local result = {}
  local total_processed = 0
  
  while total_processed < #sanitized do
    local chunk_end = math.min(total_processed + chunk_size, #sanitized)
    local chunk = string.sub(sanitized, total_processed + 1, chunk_end)
    local bytes = {chunk:byte(1, -1)}
    local i = 1
    
    while i <= #bytes do
      local b = bytes[i]
      local width = 1
      
      if b >= 240 and b <= 247 then -- 4-byte sequence
        width = 4
      elseif b >= 224 and b <= 239 then -- 3-byte sequence
        width = 3
      elseif b >= 192 and b <= 223 then -- 2-byte sequence
        width = 2
      end
      
      -- Check if we have a complete sequence
      local valid = true
      if width > 1 then
        for j = 1, width - 1 do
          if i + j > #bytes or not is_continuation_byte(bytes[i + j]) then
            valid = false
            break
          end
        end
      end
      
      if valid then
        for j = 0, width - 1 do
          table.insert(result, bytes[i + j])
        end
        i = i + width
      else
        table.insert(result, 63) -- '?' character
        i = i + 1
      end
    end
    
    total_processed = chunk_end
  end
  
  sanitized = ""
  for _, b in ipairs(result) do
    sanitized = sanitized .. string.char(b)
  end
  
  if config.debug_mode then
    if sanitized ~= text then
      print("[Nudge Two Hats Debug] Text sanitized for UTF-8 compliance")
    end
  end
  
  return sanitized
end

local function translate_with_gemini(text, source_lang, target_lang, api_key)
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Translating: " .. text)
  end
  
  local sanitized_text = sanitize_text(text)
  
  local prompt
  if target_lang == "ja" then
    prompt = "以下の" .. 
             (source_lang == "ja" and "日本語" or "英語") .. 
             "テキストを日本語に翻訳してください。簡潔に、元の意味を維持してください。必ず日本語で回答してください: " .. sanitized_text
  else
    prompt = "Translate the following " .. 
             (source_lang == "ja" and "Japanese" or "English") .. 
             " text to English. Keep it concise and maintain the original meaning. Always respond in English: " .. sanitized_text
  end
  
  local request_data
  local ok, encoded = pcall(vim.fn.json_encode, {
    contents = {
      {
        parts = {
          {
            text = prompt
          }
        }
      }
    },
    generationConfig = {
      temperature = 0.1,
      topK = 40,
      topP = 0.95,
      maxOutputTokens = 1024
    }
  })
  
  if not ok then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] JSON encoding failed: " .. tostring(encoded))
    end
    return nil
  end
  
  request_data = encoded
  
  local endpoint = config.api_endpoint:gsub("[<>]", "")
  local full_url = endpoint .. "?key=" .. api_key
  local temp_file = "/tmp/nudge_two_hats_translation.json"
  
  local req_file = io.open(temp_file, "w")
  if req_file then
    req_file:write(request_data)
    req_file:close()
  end
  
  local curl_command = string.format(
    "curl -s -X POST %s -H 'Content-Type: application/json' -d @%s",
    full_url,
    temp_file
  )
  
  local output = vim.fn.system(curl_command)
  
  local ok, response
  if vim.json and vim.json.decode then
    ok, response = pcall(vim.json.decode, output)
  else
    ok, response = pcall(function() return vim.fn.json_decode(output) end)
  end
  
  if ok and response and response.candidates and response.candidates[1] and 
     response.candidates[1].content and response.candidates[1].content.parts and 
     response.candidates[1].content.parts[1] and response.candidates[1].content.parts[1].text then
    local translated = response.candidates[1].content.parts[1].text
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Translation result: " .. translated)
    end
    
    return translated
  end
  
  return nil
end

local function translate_message(message)
  if not config.translate_messages then
    return message
  end
  
  local target_lang = get_language()
  
  for key, value in pairs(translations[target_lang]) do
    if message == value then
      return message -- Already in target language
    end
  end
  
  for key, value in pairs(translations.en) do
    if message == value and translations[target_lang][key] then
      return translations[target_lang][key]
    end
  end
  
  for key, value in pairs(translations.ja) do
    if message == value and translations[target_lang][key] then
      return translations[target_lang][key]
    end
  end
  
  if config.translate_messages and target_lang ~= "en" and not is_japanese(message) then
    if target_lang == "ja" and message:len() < 100 then
      local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
      if api_key then
        local translated = translate_with_gemini(message, "en", "ja", api_key)
        if translated then
          return translated
        end
      end
    end
  elseif config.translate_messages and target_lang ~= "ja" and is_japanese(message) then
    if target_lang == "en" and message:len() < 100 then
      local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
      if api_key then
        local translated = translate_with_gemini(message, "ja", "en", api_key)
        if translated then
          return translated
        end
      end
    end
  end
  
  return message
end


local function get_buf_diff(buf)
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  
  -- Get the filetypes for this buffer
  local filetypes = {}
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  else
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
    end
  end
  
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
  
  -- Check for diff in any of the filetypes
  for _, filetype in ipairs(filetypes) do
    local old = state.buf_content_by_filetype[buf][filetype]
    
    if not old and state.buf_content[buf] then
      old = state.buf_content[buf]
    end
    
    if old and old ~= content then
      local diff = vim.diff(old, content, { result_type = "unified" })
      if type(diff) == "string" then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] Found diff for filetype: %s", filetype))
        end
        return content, diff, filetype
      end
    end
  end
  
  return content, nil, nil
end

local selected_hat = nil

local function get_prompt_for_buffer(buf)
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
    if filetype and config.filetype_prompts[filetype] then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Using filetype-specific prompt for: " .. filetype)
      end
      
      local filetype_prompt = config.filetype_prompts[filetype]
      
      if type(filetype_prompt) == "string" then
        selected_hat = nil
        return filetype_prompt
      elseif type(filetype_prompt) == "table" then
        local role = filetype_prompt.role or config.default_cbt.role
        local direction = filetype_prompt.direction or config.default_cbt.direction
        local emotion = filetype_prompt.emotion or config.default_cbt.emotion
        local tone = filetype_prompt.tone or config.default_cbt.tone
        local prompt_text = filetype_prompt.prompt
        
        local hats = filetype_prompt.hats or config.default_cbt.hats or {}
        
        if #hats > 0 then
          math.randomseed(os.time())
          selected_hat = hats[math.random(1, #hats)]
          
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Selected hat: " .. selected_hat)
          end
        end
        
        return string.format("I am a %s wearing the %s hat. %s. With %s emotions and a %s tone, I will advise: %s", 
                             role, selected_hat, direction, emotion, tone, prompt_text)
      else
        selected_hat = nil
        return string.format("I am a %s. %s. With %s emotions and a %s tone, I will advise: %s", 
                             role, direction, emotion, tone, prompt_text)
      end
    end
  end
  
  selected_hat = nil
  return config.system_prompt
end

local function get_gemini_advice(diff, callback, prompt, purpose)
  local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
  
  if not api_key then
    local error_msg = translate_message(translations.en.api_key_not_set)
    vim.notify(error_msg, vim.log.levels.ERROR)
    return
  end

  local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
  if log_file then
    log_file:write("--- New API Request ---\n")
    log_file:write("Timestamp: " .. os.date() .. "\n")
    log_file:write("API Key: " .. string.sub(api_key, 1, 5) .. "...\n")
    log_file:write("Endpoint: " .. config.api_endpoint .. "\n")
    if prompt then
      log_file:write("Using prompt: " .. prompt .. "\n")
    end
    log_file:close()
  end

  local system_prompt = prompt or config.system_prompt
  
  local purpose_text = purpose or config.purpose
  if purpose_text and purpose_text ~= "" then
    system_prompt = system_prompt .. "\n\nWork purpose: " .. purpose_text
  end
  
  local output_lang = get_language()
  if output_lang == "ja" then
    system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。%d文字程度の簡潔なアドバイスをお願いします。", config.message_length)
  else
    system_prompt = system_prompt .. string.format("\nPlease respond in English. Provide concise advice in about %d characters.", config.message_length)
  end
  
  local sanitized_diff = sanitize_text(diff)
  if config.debug_mode and sanitized_diff ~= diff then
    print("[Nudge Two Hats Debug] Diff content sanitized for UTF-8 compliance")
  end
  
  local ok, request_data = pcall(vim.fn.json_encode, {
    contents = {
      {
        parts = {
          {
            text = system_prompt .. "\n\n" .. sanitized_diff
          }
        }
      }
    },
    generationConfig = {
      thinkingConfig = {
        thinkingBudget = 0
      },
      temperature = 0.2,
      topK = 40,
      topP = 0.95,
      maxOutputTokens = 1024
    }
  })
  
  if not ok then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] JSON encoding failed: " .. tostring(request_data))
    end
    local error_msg = translate_message(translations.en.api_error)
    vim.notify(error_msg .. ": JSON encoding failed", vim.log.levels.ERROR)
    callback(translate_message(translations.en.api_error))
    return
  end

  local has_plenary, curl = pcall(require, "plenary.curl")
  
  if has_plenary then
    local endpoint = config.api_endpoint:gsub("[<>]", "")
    local full_url = endpoint .. "?key=" .. api_key
    
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using plenary.curl\n")
      log_file:write("Clean endpoint: " .. endpoint .. "\n")
      log_file:write("Full URL (sanitized): " .. string.gsub(full_url, api_key, string.sub(api_key, 1, 5) .. "...") .. "\n")
      log_file:close()
    end
    
    curl.post(full_url, {
      headers = {
        ["Content-Type"] = "application/json",
      },
      body = request_data,
      callback = function(response)
        vim.schedule(function()
          if response.status == 200 and response.body then
            local ok, result
            if vim.json and vim.json.decode then
              ok, result = pcall(vim.json.decode, response.body)
            else
              ok, result = pcall(function() return vim.fn.json_decode(response.body) end)
            end
            
            if ok and result and result.candidates and result.candidates[1] and 
               result.candidates[1].content and result.candidates[1].content.parts and 
               result.candidates[1].content.parts[1] and result.candidates[1].content.parts[1].text then
              local advice = result.candidates[1].content.parts[1].text
              
              if config.length_type == "characters" then
                if #advice > config.message_length then
                  advice = safe_truncate(advice, config.message_length)
                end
              else
                local words = {}
                for word in advice:gmatch("%S+") do
                  table.insert(words, word)
                end
                
                if #words > config.message_length then
                  local truncated_words = {}
                  for i = 1, config.message_length do
                    table.insert(truncated_words, words[i])
                  end
                  advice = table.concat(truncated_words, " ")
                end
              end
              
              if config.translate_messages then
                advice = translate_message(advice)
              end
              
              callback(advice)
              
              config.execution_delay = generate_random_delay()
            else
              callback(translate_message(translations.en.api_error))
            end
          else
            local error_msg = translate_message(translations.en.api_error)
            vim.notify(error_msg .. ": " .. (response.body or translate_message(translations.en.unknown_error)), vim.log.levels.ERROR)
            callback(translate_message(translations.en.api_error))
          end
        end)
      end
    })
  else
    local endpoint = config.api_endpoint:gsub("[<>]", "")
    local full_url = endpoint .. "?key=" .. api_key
    local temp_file = "/tmp/nudge_two_hats_request.json"
    
    local req_file = io.open(temp_file, "w")
    if req_file then
      req_file:write(request_data)
      req_file:close()
    end
    
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using curl fallback\n")
      log_file:write("Clean endpoint: " .. endpoint .. "\n")
      log_file:write("Full URL (sanitized): " .. string.gsub(full_url, api_key, string.sub(api_key, 1, 5) .. "...") .. "\n")
      log_file:write("Command: curl -s -X POST " .. endpoint .. "?key=" .. string.sub(api_key, 1, 5) .. "... -H 'Content-Type: application/json' -d @" .. temp_file .. "\n")
      log_file:close()
    end
    
    local curl_command = string.format(
      "curl -s -X POST %s -H 'Content-Type: application/json' -d @%s",
      full_url,
      temp_file
    )
    
    vim.fn.jobstart(curl_command, {
      on_stdout = function(_, data)
        if data and #data > 0 and data[1] ~= "" then
          vim.schedule(function()
            local ok, response
            if vim.json and vim.json.decode then
              ok, response = pcall(vim.json.decode, table.concat(data, "\n"))
            else
              ok, response = pcall(function() return vim.fn.json_decode(table.concat(data, "\n")) end)
            end
            
            if ok and response and response.candidates and response.candidates[1] and 
               response.candidates[1].content and response.candidates[1].content.parts and 
               response.candidates[1].content.parts[1] and response.candidates[1].content.parts[1].text then
              local advice = response.candidates[1].content.parts[1].text
              
              if config.length_type == "characters" then
                if #advice > config.message_length then
                  advice = safe_truncate(advice, config.message_length)
                end
              else
                local words = {}
                for word in advice:gmatch("%S+") do
                  table.insert(words, word)
                end
                
                if #words > config.message_length then
                  local truncated_words = {}
                  for i = 1, config.message_length do
                    table.insert(truncated_words, words[i])
                  end
                  advice = table.concat(truncated_words, " ")
                end
              end
              
              if config.translate_messages then
                advice = translate_message(advice)
              end
              
              callback(advice)
              
              config.execution_delay = generate_random_delay()
            else
              callback(translate_message(translations.en.api_error))
            end
          end)
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 0 and data[1] ~= "" then
          vim.schedule(function()
            local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
            if log_file then
              log_file:write("Curl stderr: " .. table.concat(data, "\n") .. "\n")
              log_file:close()
            end
            
            local error_msg = translate_message(translations.en.api_error)
            vim.notify(error_msg .. ": " .. table.concat(data, "\n"), vim.log.levels.ERROR)
          end)
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          vim.schedule(function()
            callback(translate_message(translations.en.api_error))
          end)
        end
      end
    })
  end
end

local function create_autocmd(buf)
  local augroup = vim.api.nvim_create_augroup("nudge-two-hats-" .. buf, {})
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  
  local filetypes = {}
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  else
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
      state.buf_filetypes[buf] = current_filetype
    end
  end
  
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
  for _, filetype in ipairs(filetypes) do
    state.buf_content_by_filetype[buf][filetype] = content
  end
  
  state.buf_content[buf] = content
  
  local current_time = os.time()
  state.virtual_text.last_cursor_move[buf] = current_time
  
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] Initialized buffer %d with filetypes: %s", 
      buf, table.concat(filetypes, ", ")))
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "BufWritePost" }, {
    group = augroup,
    buffer = buf,
    callback = function(ctx)
      if not state.enabled then
        return
      end

      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          state.buf_content[buf] = nil
          state.buf_content_by_filetype[buf] = nil
          vim.api.nvim_del_augroup_by_id(augroup)
          return
        end

        local content, diff, diff_filetype = get_buf_diff(buf)
        
        if not diff then
          return
        end

        -- Check if current filetype is in the list of registered filetypes
        local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        local filetype_match = false
        
        if state.buf_filetypes[buf] then
          for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
            if filetype == current_filetype then
              filetype_match = true
              break
            end
          end
        end
        
        if not filetype_match then
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] スキップ：現在のfiletype (%s) が登録されたfiletypes (%s) に含まれていません", 
              current_filetype or "nil", state.buf_filetypes[buf] or "nil"))
          end
          return
        end

        for _, filetype in ipairs(filetypes) do
          if not state.buf_content_by_filetype[buf] then
            state.buf_content_by_filetype[buf] = {}
          end
          state.buf_content_by_filetype[buf][filetype] = content
        end
        
        state.buf_content[buf] = content
        
        -- Check if minimum interval has passed since last API call
        local current_time = os.time()
        local random_interval = math.random(0, config.min_interval * 60)
        if (current_time - state.last_api_call) < random_interval then
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] Skipping API call - minimum interval not reached. Last call: %s, Current time: %s, Random interval: %d seconds",
              os.date("%c", state.last_api_call),
              os.date("%c", current_time),
              random_interval))
          end
          return
        end
        
        state.last_api_call = current_time
        
        if config.debug_mode then
          print("[Nudge Two Hats Debug] Sending diff to Gemini API for filetype: " .. (diff_filetype or "unknown"))
          print(diff)
        end
        
        -- Get the appropriate prompt for this buffer's filetype
        local prompt = get_prompt_for_buffer(buf)
        
        get_gemini_advice(diff, function(advice)
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Advice: " .. advice)
          end
          
          local title = "Nudge Two Hats"
          if selected_hat then
            title = selected_hat
          end
          
          vim.notify(advice, vim.log.levels.INFO, {
            title = title,
            icon = "🎩",
          })
          
          state.virtual_text.last_advice[buf] = advice
          
          config.execution_delay = generate_random_delay()
        end, prompt, config.purpose)
      end, config.execution_delay)
    end,
  })
end

local function start_notification_timer(buf, event_name)
  if not state.enabled then
    return
  end
  
  -- Check if this is the current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    return
  end
  
  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  if state.virtual_text.timers[buf] then
    return
  end
  
  local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
  if log_file then
    log_file:write("=== " .. event_name .. " triggered timer start at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    log_file:write("Buffer: " .. buf .. "\n")
  end
  
  local timer_ms = config.virtual_text.idle_time * 60 * 1000 -- Convert minutes to milliseconds
  
  local current_log_file = log_file
  log_file = nil -- Set to nil to prevent double closing
  
  -- Set up notification timer that won't be canceled by cursor movement
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Starting notification timer for buffer " .. buf .. " from " .. event_name .. " (initial 5s delay)")
  end
  
  -- Always print this message regardless of debug mode to ensure timer activation is visible
  print("[Nudge Two Hats] Timer activated for buffer " .. buf .. " from " .. event_name .. " at " .. os.date("%H:%M:%S"))
  
  state.virtual_text.timers[buf] = vim.fn.timer_start(5000, function()
    if current_log_file then
      pcall(function() current_log_file:close() end)
      current_log_file = nil
    end
    
    vim.schedule(function()
      print("[Nudge Two Hats] Initial notification timer fired at " .. os.date("%H:%M:%S"))
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Initial notification timer fired at " .. os.date("%H:%M:%S"))
      end
    end)
    
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    local timer_log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if timer_log_file then
      timer_log_file:write("=== Initial virtual text timer fired at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      timer_log_file:write("Buffer: " .. buf .. "\n")
      timer_log_file:write("Timer ID: " .. state.virtual_text.timers[buf] .. "\n")
    end
    
    if timer_log_file then
      timer_log_file:write("Setting up Gemini API timer\n")
    end
    
    -- Store the timer ID in the state
    vim.schedule(function()
      print("[Nudge Two Hats] Starting Gemini API timer for buffer " .. buf .. " (delay: " .. (timer_ms/1000) .. "s)")
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Starting Gemini API timer for buffer " .. buf .. " (delay: " .. (timer_ms/1000) .. "s)")
      end
    end)
    
    state.virtual_text.timers[buf] = vim.fn.timer_start(timer_ms, function()
      vim.schedule(function()
        print("[Nudge Two Hats] Gemini API timer fired at " .. os.date("%H:%M:%S") .. " for buffer " .. buf)
        if config.debug_mode then
          print("[Nudge Two Hats Debug] Gemini API timer fired at " .. os.date("%H:%M:%S") .. " for buffer " .. buf)
        end
      end)
    end)
  end)
end

local function setup_virtual_text(buf)
  -- Store the last cursor position to detect actual movement
  state.virtual_text.last_cursor_pos = state.virtual_text.last_cursor_pos or {}
  state.virtual_text.last_cursor_pos[buf] = nil -- Initialize to nil to force update on first move
  
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      local current_pos = vim.api.nvim_win_get_cursor(0)
      local cursor_row = current_pos[1]
      local cursor_col = current_pos[2]
      
      -- Check if cursor has actually moved from its previous position
      local last_pos = state.virtual_text.last_cursor_pos[buf]
      local cursor_actually_moved = true
      
      if last_pos then
        cursor_actually_moved = (last_pos.row ~= cursor_row or last_pos.col ~= cursor_col)
      end
      
      state.virtual_text.last_cursor_pos[buf] = { row = cursor_row, col = cursor_col }
      
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
      if log_file then
        log_file:write("=== CursorMoved triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
        log_file:write("Buffer: " .. buf .. "\n")
        log_file:write("Current position: row=" .. cursor_row .. ", col=" .. cursor_col .. "\n")
        if last_pos then
          log_file:write("Previous position: row=" .. last_pos.row .. ", col=" .. last_pos.col .. "\n")
        else
          log_file:write("Previous position: nil (first move)\n")
        end
        log_file:write("Cursor actually moved: " .. tostring(cursor_actually_moved) .. "\n")
      end
      
      if cursor_actually_moved then
        local old_time = state.virtual_text.last_cursor_move[buf] or 0
        local new_time = os.time()
        state.virtual_text.last_cursor_move[buf] = new_time
        
        if log_file then
          log_file:write("Updated last_cursor_move from " .. old_time .. " to " .. new_time .. "\n")
        end
        
        if state.virtual_text.extmarks[buf] then
          M.clear_virtual_text(buf)
        end
        
        if log_file then
          log_file:write("Cursor moved but not stopping virtual text timer\n")
        end
      else
        if log_file then
          log_file:write("Cursor didn't actually move, not updating last_cursor_move time\n")
        end
      end
      
      if log_file then
        log_file:close()
      end
    end,
  })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    buffer = buf,
    callback = function()
      start_notification_timer(buf, "BufWritePost")
    end,
  })
  
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    buffer = buf,
    callback = function()
      start_notification_timer(buf, "InsertLeave")
    end,
  })
  
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    buffer = buf,
    callback = function()
      start_notification_timer(buf, "BufReadPost")
    end,
  })
  
  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup,
    buffer = buf,
    callback = function()
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
      if log_file then
        log_file:write("=== CursorHold triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
        log_file:write("Buffer: " .. buf .. "\n")
        log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
        log_file:write("updatetime: " .. vim.o.updatetime .. "ms\n")
        log_file:write("idle_time setting: " .. config.virtual_text.idle_time .. " minutes (" .. (config.virtual_text.idle_time * 60) .. " seconds)\n")
      end
      
      if not state.enabled then
        if log_file then
          log_file:write("Plugin not enabled, exiting CursorHold handler\n\n")
          log_file:close()
        end
        return
      end
      
      -- Check if this is the current buffer
      local current_buf = vim.api.nvim_get_current_buf()
      if buf ~= current_buf then
        if log_file then
          log_file:write("Buffer " .. buf .. " is not the current buffer (" .. current_buf .. "), skipping timer setup\n\n")
          log_file:close()
        end
        return
      end
      
      -- Check if cursor has been idle for the required time
      local current_time = os.time()
      local last_cursor_move_time = state.virtual_text.last_cursor_move[buf] or 0
      local idle_time = current_time - last_cursor_move_time
      local required_idle_time = (config.virtual_text.cursor_idle_delay or 5) * 60 -- Convert minutes to seconds
      local idle_condition_met = idle_time >= required_idle_time
      
      if log_file then
        log_file:write("Current time: " .. os.date("%Y-%m-%d %H:%M:%S", current_time) .. "\n")
        log_file:write("Last cursor move time: " .. os.date("%Y-%m-%d %H:%M:%S", last_cursor_move_time) .. "\n")
        log_file:write("Idle time: " .. idle_time .. " seconds\n")
        log_file:write("Required idle time: " .. required_idle_time .. " seconds\n")
        log_file:write("Idle condition met: " .. tostring(idle_condition_met) .. "\n")
      end
      
      -- Only set up timer if cursor has been idle for the required time
      if idle_condition_met and not state.virtual_text.timers[buf] then
        if log_file then
          log_file:close()
        end
        
        start_notification_timer(buf, "CursorHold")
      else
        if log_file then
          log_file:close()
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      state.buf_content[buf] = nil
      state.buf_filetypes[buf] = nil
      state.virtual_text.last_advice[buf] = nil
      state.virtual_text.last_cursor_move[buf] = nil
      M.clear_virtual_text(buf)
      
      vim.api.nvim_del_augroup_by_id(augroup)
      return true
    end,
  })
end

function M.clear_virtual_text(buf)
  if not state.virtual_text.namespace or not state.virtual_text.extmarks[buf] then
    return
  end
  
  vim.api.nvim_buf_del_extmark(buf, state.virtual_text.namespace, state.virtual_text.extmarks[buf])
  state.virtual_text.extmarks[buf] = nil
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Virtual text cleared")
  end
end

function M.stop_timer(buf)
  if state.virtual_text.timers[buf] then
    local timer_id = state.virtual_text.timers[buf]
    vim.fn.timer_stop(timer_id)
    state.virtual_text.timers[buf] = nil
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Stopped timer %d for buffer %d", timer_id, buf))
    end
    
    return timer_id
  end
  
  return nil
end

function M.display_virtual_text(buf, advice)
  local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
  if log_file then
    log_file:write("=== display_virtual_text called at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    log_file:write("Buffer: " .. buf .. "\n")
    log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
    log_file:write("Advice length: " .. #advice .. " characters\n")
    log_file:write("Advice: " .. advice .. "\n")
  end
  
  if not state.enabled then
    if log_file then
      log_file:write("Plugin not enabled, exiting display_virtual_text\n\n")
      log_file:close()
    end
    return
  end
  
  if not state.virtual_text.namespace then
    state.virtual_text.namespace = vim.api.nvim_create_namespace("nudge-two-hats-virtual-text")
    if log_file then
      log_file:write("Created new namespace: nudge-two-hats-virtual-text\n")
    end
  end
  
  M.clear_virtual_text(buf)
  
  M.stop_timer(buf)
  
  if log_file then
    log_file:write("Reset timer for buffer " .. buf .. " when displaying virtual text\n")
  end
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Reset timer for buffer " .. buf .. " when displaying virtual text")
  end
  
  local ok, cursor_pos = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok then
    if log_file then
      log_file:write("Error getting cursor position: " .. tostring(cursor_pos) .. "\n")
      log_file:write("Exiting display_virtual_text\n\n")
      log_file:close()
    end
    return
  end
  
  local row = cursor_pos[1] - 1 -- Convert to 0-indexed
  
  if log_file then
    log_file:write("Cursor position: line " .. (row + 1) .. ", col " .. cursor_pos[2] .. "\n")
  end
  
  state.virtual_text.last_advice[buf] = advice
  
  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, buf, state.virtual_text.namespace, row, 0, {
    virt_text = {{advice, "NudgeTwoHatsVirtualText"}},
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
  
  if not ok then
    if log_file then
      log_file:write("Error setting extmark: " .. tostring(extmark_id) .. "\n")
      log_file:write("Exiting display_virtual_text\n\n")
      log_file:close()
    end
    return
  end
  
  state.virtual_text.extmarks[buf] = extmark_id
  
  if log_file then
    log_file:write("Successfully set extmark with ID: " .. extmark_id .. "\n")
    log_file:write("Virtual text should now be visible at line " .. (row + 1) .. "\n\n")
    log_file:close()
  end
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Virtual text displayed at line " .. (row + 1))
  end
end

function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end
  
  vim.api.nvim_set_hl(0, "NudgeTwoHatsVirtualText", {
    fg = config.virtual_text.text_color,
    bg = config.virtual_text.background_color,
  })
  
  state.virtual_text.namespace = vim.api.nvim_create_namespace("nudge-two-hats-virtual-text")
  
  vim.api.nvim_create_user_command("NudgeTwoHatsToggle", function(args)
    state.enabled = not state.enabled
    local status = state.enabled and translate_message(translations.en.enabled) or translate_message(translations.en.disabled)
    vim.notify("Nudge Two Hats " .. status, vim.log.levels.INFO)
    
    if state.enabled then
      if not state.original_updatetime then
        state.original_updatetime = vim.o.updatetime
      end
      vim.o.updatetime = 1000
      
      local buf = vim.api.nvim_get_current_buf()
      local filetypes = {}
      
      if args.args and args.args ~= "" then
        for filetype in string.gmatch(args.args, "%S+") do
          table.insert(filetypes, filetype)
        end
        -- print("[Nudge Two Hats] Using specified filetypes: " .. args.args)
      else
        local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        if current_filetype and current_filetype ~= "" then
          table.insert(filetypes, current_filetype)
          -- print("[Nudge Two Hats] Using current buffer's filetype: " .. current_filetype)
        end
      end
      
      -- Store the filetypes in state
      state.buf_filetypes[buf] = table.concat(filetypes, ",")
      
      local augroup_name = "nudge-two-hats-" .. buf
      pcall(vim.api.nvim_del_augroup_by_name, augroup_name)
      
      create_autocmd(buf)
      
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      -- print("[Nudge Two Hats] Registered autocmds for buffer " .. buf .. " with filetypes: " .. state.buf_filetypes[buf])
      -- print("[Nudge Two Hats] CursorHold should now trigger every " .. vim.o.updatetime .. "ms")
      -- print("[Nudge Two Hats] Virtual text should appear after " .. config.virtual_text.idle_time .. " minutes of idle cursor")
      
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Set updatetime to 1000ms (original: " .. state.original_updatetime .. "ms)")
      end
    else
      if state.original_updatetime then
        vim.o.updatetime = state.original_updatetime
        
        if config.debug_mode then
          print("[Nudge Two Hats Debug] Restored updatetime to " .. state.original_updatetime .. "ms")
        end
      end
      
      for buf, _ in pairs(state.virtual_text.extmarks) do
        if vim.api.nvim_buf_is_valid(buf) then
          M.clear_virtual_text(buf)
        end
      end
      
      for buf, timer_id in pairs(state.virtual_text.timers) do
        if timer_id then
          vim.fn.timer_stop(timer_id)
          state.virtual_text.timers[buf] = nil
          
          if log_file then
            log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
            if log_file then
              log_file:write("Stopping virtual text timer with ID: " .. timer_id .. " when disabling plugin\n")
              log_file:close()
            end
          end
        end
      end
    end
  end, {})

  vim.api.nvim_create_user_command("NudgeTwoHatsSetApiKey", function(args)
    state.api_key = args.args
    vim.notify(translate_message(translations.en.api_key_set), vim.log.levels.INFO)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("NudgeTwoHatsStart", function(args)
    local buf = vim.api.nvim_get_current_buf()
    local filetypes = {}
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    local using_current_filetype = false
    local file_paths = {}
    
    if args.args and args.args ~= "" then
      for file_path in string.gmatch(args.args, "%S+") do
        table.insert(file_paths, file_path)
      end
      
      for _, file_path in ipairs(file_paths) do
        -- Check if file exists
        local file_exists = vim.fn.filereadable(file_path) == 1
        
        if file_exists then
          local file_buf = vim.fn.bufadd(file_path)
          vim.fn.bufload(file_buf)
          local file_filetype = vim.api.nvim_buf_get_option(file_buf, "filetype")
          
          if file_filetype and file_filetype ~= "" then
            table.insert(filetypes, file_filetype)
            
            -- Set up timer events for this file's buffer
            state.buf_filetypes[file_buf] = file_filetype
            state.virtual_text.last_cursor_move = state.virtual_text.last_cursor_move or {}
            state.virtual_text.last_cursor_move[file_buf] = os.time()
            
            create_autocmd(file_buf)
            setup_virtual_text(file_buf)
            
            -- print("[Nudge Two Hats] Added file: " .. file_path .. " with filetype: " .. file_filetype)
          else
            -- print("[Nudge Two Hats] Warning: Could not determine filetype for " .. file_path)
          end
        else
          -- print("[Nudge Two Hats] Warning: File does not exist: " .. file_path)
        end
      end
      
      -- print("[Nudge Two Hats] Using specified file paths: " .. args.args)
    else
      -- No arguments, use current buffer
      if current_filetype and current_filetype ~= "" then
        table.insert(filetypes, current_filetype)
        using_current_filetype = true
        -- print("[Nudge Two Hats] Using current buffer's filetype: " .. current_filetype)
      end
    end
    
    -- Store the filetypes in state for current buffer
    if #filetypes > 0 then
      state.buf_filetypes[buf] = table.concat(filetypes, ",")
    end
    
    -- Set up virtual text and updatetime
    if not state.original_updatetime then
      state.original_updatetime = vim.o.updatetime
    end
    vim.o.updatetime = 1000
    
    -- Initialize virtual text state for current buffer if no file paths were specified
    if #file_paths == 0 then
      state.virtual_text.last_cursor_move = state.virtual_text.last_cursor_move or {}
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      create_autocmd(buf)
      setup_virtual_text(buf)
    end
    
    state.enabled = true
    
    create_autocmd(buf)
    setup_virtual_text(buf)
    
    -- vim.notify(translate_message(translations.en.started_buffer), vim.log.levels.INFO)
    
    local should_show_notification = true
    if current_filetype and current_filetype ~= "" then
      for _, filetype in ipairs(filetypes) do
        if filetype == current_filetype then
          should_show_notification = false
          break
        end
      end
    end
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Set updatetime to 1000ms (original: " .. state.original_updatetime .. "ms)")
      print("[Nudge Two Hats Debug] Virtual text should appear after " .. config.virtual_text.idle_time .. " minutes of idle cursor")
      print("[Nudge Two Hats Debug] Cursor idle delay: " .. (config.virtual_text.cursor_idle_delay or 5) .. " minutes")
      print("[Nudge Two Hats Debug] Registered filetypes: " .. table.concat(filetypes, ", "))
      print("[Nudge Two Hats Debug] Current filetype: " .. (current_filetype or "nil"))
      print("[Nudge Two Hats Debug] Processed file paths: " .. table.concat(file_paths, ", "))
    end
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugToggle", function()
    config.debug_mode = not config.debug_mode
    local status = config.debug_mode and translate_message(translations.en.enabled) or translate_message(translations.en.disabled)
    vim.notify("Nudge Two Hats debug mode " .. status, vim.log.levels.INFO)
    if config.debug_mode then
      print(translate_message(translations.en.debug_enabled))
    end
  end, {})
  
  -- Store debug autocmd group ID by buffer
  state.debug_augroup_ids = state.debug_augroup_ids or {}
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugVirtualText", function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    M.clear_virtual_text(buf)
    
    if state.debug_augroup_ids[buf] then
      pcall(vim.api.nvim_del_augroup_by_id, state.debug_augroup_ids[buf])
      state.debug_augroup_ids[buf] = nil
    end
    
    local augroup_name = "nudge-two-hats-debug-" .. buf
    local augroup_id = vim.api.nvim_create_augroup(augroup_name, { clear = true })
    state.debug_augroup_ids[buf] = augroup_id
    
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = get_prompt_for_buffer(buf)
    
    local fake_diff = "This is a test diff for debugging purposes.\n"
    
    local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if filetype and filetype ~= "" then
      fake_diff = fake_diff .. "Filetype: " .. filetype .. "\n"
      fake_diff = fake_diff .. "Sample code or content changes for " .. filetype .. " files.\n"
    end
    
    fake_diff = fake_diff .. "Added some new functionality.\n"
    fake_diff = fake_diff .. "Refactored some existing code.\n"
    fake_diff = fake_diff .. "Fixed a few bugs.\n"
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using prompt: " .. prompt)
      print("[Nudge Two Hats Debug] Using fake diff for debug: " .. fake_diff)
    end
    
    local current_pos = vim.api.nvim_win_get_cursor(0)
    state.debug_cursor_pos = { row = current_pos[1], col = current_pos[2] }
    
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup_id,
      buffer = buf,
      callback = function()
        if state.debug_cursor_pos then
          local new_pos = vim.api.nvim_win_get_cursor(0)
          if new_pos[1] ~= state.debug_cursor_pos.row or new_pos[2] ~= state.debug_cursor_pos.col then
            M.clear_virtual_text(buf)
            vim.notify("Virtual text cleared on cursor movement", vim.log.levels.INFO)
            pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
            state.debug_augroup_ids[buf] = nil
            state.debug_cursor_pos = nil
          end
        end
      end
    })
    
    vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
      group = augroup_id,
      buffer = buf,
      callback = function()
        pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
        state.debug_augroup_ids[buf] = nil
        return true
      end
    })
    
    local loading_message = "Loading advice from AI..."
    state.virtual_text.last_advice[buf] = loading_message
    M.display_virtual_text(buf, loading_message)
    
    vim.notify("Loading virtual text advice...", vim.log.levels.INFO)
    
    get_gemini_advice(fake_diff, function(advice)
      if vim.api.nvim_buf_is_valid(buf) then
        state.virtual_text.last_advice[buf] = advice
        
        if state.virtual_text.extmarks[buf] then
          M.display_virtual_text(buf, advice)
          
          vim.notify("Debug virtual text updated with AI advice", vim.log.levels.INFO)
          
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Virtual text message displayed")
            print("[Nudge Two Hats Debug] Current updatetime: " .. vim.o.updatetime)
            print("[Nudge Two Hats Debug] Plugin enabled: " .. tostring(state.enabled))
            print("[Nudge Two Hats Debug] Move cursor to clear virtual text")
          end
        end
      end
    end, prompt, config.purpose)
  end, {})
  
  -- Store timer IDs by buffer
  state.debug_timers = state.debug_timers or {}
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugVirtualTextTimer", function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    M.clear_virtual_text(buf)
    
    if state.debug_timers[buf] then
      vim.fn.timer_stop(state.debug_timers[buf])
      state.debug_timers[buf] = nil
    end
    
    if state.debug_augroup_ids[buf] then
      pcall(vim.api.nvim_del_augroup_by_id, state.debug_augroup_ids[buf])
      state.debug_augroup_ids[buf] = nil
    end
    
    local augroup_name = "nudge-two-hats-debug-timer-" .. buf
    local augroup_id = vim.api.nvim_create_augroup(augroup_name, { clear = true })
    state.debug_augroup_ids[buf] = augroup_id
    
    local current_pos = vim.api.nvim_win_get_cursor(0)
    state.debug_cursor_pos = { row = current_pos[1], col = current_pos[2] }
    
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup_id,
      buffer = buf,
      callback = function()
        if state.debug_cursor_pos then
          local new_pos = vim.api.nvim_win_get_cursor(0)
          if new_pos[1] ~= state.debug_cursor_pos.row or new_pos[2] ~= state.debug_cursor_pos.col then
            if state.debug_timers[buf] then
              vim.fn.timer_stop(state.debug_timers[buf])
              state.debug_timers[buf] = nil
            end
            
            M.clear_virtual_text(buf)
            
            vim.notify("Timer stopped and virtual text cleared on cursor movement", vim.log.levels.INFO)
            
            pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
            state.debug_augroup_ids[buf] = nil
            state.debug_cursor_pos = nil
          end
        end
      end
    })
    
    vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
      group = augroup_id,
      buffer = buf,
      callback = function()
        if state.debug_timers[buf] then
          vim.fn.timer_stop(state.debug_timers[buf])
          state.debug_timers[buf] = nil
        end
        
        pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
        state.debug_augroup_ids[buf] = nil
        return true
      end
    })
    
    local initial_message = "Loading advice from AI..."
    state.virtual_text.last_advice[buf] = initial_message
    M.display_virtual_text(buf, initial_message)
    
    vim.notify("Debug timer started - will display nudge messages every 10 seconds", vim.log.levels.INFO)
    
    get_gemini_advice(fake_diff, function(advice)
      if vim.api.nvim_buf_is_valid(buf) and state.debug_cursor_pos then
        state.virtual_text.last_advice[buf] = advice
        M.display_virtual_text(buf, advice)
      end
    end, prompt, config.purpose)
    
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = get_prompt_for_buffer(buf)
    
    local fake_diff = "This is a test diff for debugging purposes.\n"
    
    local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if filetype and filetype ~= "" then
      fake_diff = fake_diff .. "Filetype: " .. filetype .. "\n"
      fake_diff = fake_diff .. "Sample code or content changes for " .. filetype .. " files.\n"
    end
    
    fake_diff = fake_diff .. "Added some new functionality.\n"
    fake_diff = fake_diff .. "Refactored some existing code.\n"
    fake_diff = fake_diff .. "Fixed a few bugs.\n"
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using prompt: " .. prompt)
      print("[Nudge Two Hats Debug] Using fake diff for debug: " .. fake_diff)
    end
    
    local function update_virtual_text()
      if not vim.api.nvim_buf_is_valid(buf) then
        if state.debug_timers[buf] then
          vim.fn.timer_stop(state.debug_timers[buf])
          state.debug_timers[buf] = nil
        end
        return
      end
      
      if state.debug_cursor_pos then
        get_gemini_advice(fake_diff, function(advice)
          if vim.api.nvim_buf_is_valid(buf) and state.debug_cursor_pos then
            state.virtual_text.last_advice[buf] = advice
            M.display_virtual_text(buf, advice)
            
            if config.debug_mode then
              print("[Nudge Two Hats Debug] Generated new advice at " .. os.date("%H:%M:%S"))
              print("[Nudge Two Hats Debug] Advice: " .. advice)
            end
          end
        end, prompt, config.purpose)
      end
    end
    
    state.debug_timers[buf] = vim.fn.timer_start(10000, function()
      if vim.api.nvim_buf_is_valid(buf) and state.debug_cursor_pos then
        update_virtual_text()
      end
      
      return 10000
    end, {["repeat"] = -1})
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsNow", function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    local current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    
    -- Get the filetypes for this buffer
    local filetypes = {}
    if state.buf_filetypes[buf] then
      for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
        table.insert(filetypes, filetype)
      end
    else
      local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
      if current_filetype and current_filetype ~= "" then
        table.insert(filetypes, current_filetype)
        -- Store the filetype for future use
        state.buf_filetypes[buf] = current_filetype
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] 初期化：現在のfiletype (%s) を保存しました", 
            current_filetype or "nil"))
        end
      end
    end
    
    if #filetypes == 0 then
      vim.notify("No filetypes specified or detected", vim.log.levels.INFO)
      return
    end
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using filetypes: " .. table.concat(filetypes, ", "))
    end
    
    local content, diff, diff_filetype = get_buf_diff(buf)
    
    if not diff then
      vim.notify(translate_message(translations.en.no_changes), vim.log.levels.INFO)
      
      for _, filetype in ipairs(filetypes) do
        if not state.buf_content_by_filetype[buf] then
          state.buf_content_by_filetype[buf] = {}
        end
        state.buf_content_by_filetype[buf][filetype] = current_content
      end
      
      state.buf_content[buf] = current_content
      
      return
    end
    
    for _, filetype in ipairs(filetypes) do
      if not state.buf_content_by_filetype[buf] then
        state.buf_content_by_filetype[buf] = {}
      end
      state.buf_content_by_filetype[buf][filetype] = current_content
    end
    
    state.buf_content[buf] = current_content
    
    state.last_api_call = 0
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Sending diff to Gemini API for filetype: " .. (diff_filetype or "unknown"))
      print(diff)
    end
    
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = get_prompt_for_buffer(buf)
    
    get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Advice: " .. advice)
      end
      
      local title = "Nudge Two Hats"
      if selected_hat then
        title = selected_hat
      end
      
      vim.notify(advice, vim.log.levels.INFO, {
        title = title,
        icon = "🎩",
      })
      
      state.virtual_text.last_advice[buf] = advice
      
      config.execution_delay = generate_random_delay()
    end, prompt, config.purpose)
  end, {})
  
  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      
      -- Only set updatetime if plugin is enabled
      if state.enabled then
        if not state.original_updatetime then
          state.original_updatetime = vim.o.updatetime
        end
        vim.o.updatetime = 1000
        
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: Switched to buffer %d", buf))
        end
        
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== BufEnter triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:write("Current buffer: " .. buf .. "\n")
          log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
          log_file:close()
        end
      end
    end
  })
  
  vim.api.nvim_create_autocmd("BufLeave", {
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      
      -- Stop any running timers for this buffer
      local timer_id = M.stop_timer(buf)
      
      if timer_id then
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== BufLeave triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:write("Leaving buffer: " .. buf .. "\n")
          log_file:write("Stopped timer: " .. timer_id .. "\n")
          log_file:close()
        end
      end
      
      -- Restore original updatetime
      if state.original_updatetime then
        vim.o.updatetime = state.original_updatetime
      end
    end
  })
end

return M
