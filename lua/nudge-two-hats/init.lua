local M = {}

local state = {
  enabled = false,
  buf_content = {}, -- Store buffer content for diff calculation (legacy, kept for backward compatibility)
  buf_content_by_filetype = {}, -- Store buffer content by buffer ID and filetype
  buf_filetypes = {}, -- Store buffer filetypes when NudgeTwoHatsStart is executed
  api_key = nil, -- Gemini API key
  last_api_call = 0, -- Timestamp of the last API call
  timers = {
    notification = {}, -- Store notification timer IDs by buffer (for API requests)
    virtual_text = {}  -- Store virtual text timer IDs by buffer (for display)
  },
  virtual_text = {
    namespace = nil, -- Namespace for virtual text extmarks
    extmarks = {}, -- Store extmark IDs by buffer
    last_advice = {}, -- Store last advice by buffer
    last_cursor_move = {}, -- Store last cursor move timestamp by buffer
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


local sanitize_cache = {}
local sanitize_cache_keys = {}
local MAX_CACHE_SIZE = 20

local function sanitize_text(text)
  if not text then
    return ""
  end
  
  if sanitize_cache[text] then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using cached sanitized text")
    end
    return sanitize_cache[text]
  end
  
  local text_hash = nil
  if #text > 1024 then
    text_hash = 0
    local step = math.max(1, math.floor(#text / 100))
    for i = 1, #text, step do
      text_hash = (text_hash * 31 + string.byte(text, i)) % 1000000007
    end
    
    if sanitize_cache[text_hash] then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Using hash-matched cached text")
      end
      return sanitize_cache[text_hash]
    end
  end
  
  local check_limit = math.min(100, #text)
  local is_ascii_only = true
  
  for i = 1, check_limit do
    local b = string.byte(text, i)
    if b >= 128 or b <= 31 or b == 34 or b == 92 or b == 127 then
      is_ascii_only = false
      break
    end
  end
  
  if is_ascii_only and #text > 100 then
    local positions = {}
    if #text > 1000 then
      for _ = 1, 10 do
        table.insert(positions, math.random(101, #text))
      end
    else
      local step = math.floor(#text / 10)
      for i = 100 + step, #text, step do
        table.insert(positions, i)
      end
    end
    
    for _, pos in ipairs(positions) do
      local b = string.byte(text, pos)
      if b >= 128 or b <= 31 or b == 34 or b == 92 or b == 127 then
        is_ascii_only = false
        break
      end
    end
  end
  
  if is_ascii_only then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Text is ASCII-only, no sanitization needed")
    end
    if text_hash then
      sanitize_cache[text_hash] = text
      table.insert(sanitize_cache_keys, text_hash)
    else
      sanitize_cache[text] = text
      table.insert(sanitize_cache_keys, text)
    end
    return text
  end
  
  if #text < 10240 then
    local sanitized = text:gsub("[\0-\31\127]", "")
    sanitized = sanitized:gsub("\\", "\\\\")
    sanitized = sanitized:gsub('"', '\\"')
    sanitized = sanitized:gsub("[\192-\193]", "?")
    sanitized = sanitized:gsub("[\245-\255]", "?")
    
    local test_ok, _ = pcall(vim.fn.json_encode, { text = sanitized })
    if test_ok then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Text sanitized using fast method")
      end
      if text_hash then
        sanitize_cache[text_hash] = sanitized
        table.insert(sanitize_cache_keys, text_hash)
      else
        sanitize_cache[text] = sanitized
        table.insert(sanitize_cache_keys, text)
      end
      return sanitized
    end
    
    local result = {}
    local result_size = 0
    local buffer_size = 1024
    local buffer = {}
    
    for i = 1, #text do
      local b = string.byte(text, i)
      
      if b <= 31 or b == 127 then
        -- Skip control characters
      elseif b == 34 then -- double quote
        table.insert(buffer, '\\"')
        result_size = result_size + 1
      elseif b == 92 then -- backslash
        table.insert(buffer, '\\\\')
        result_size = result_size + 1
      elseif b >= 128 and b <= 191 then
        table.insert(buffer, "?")
        result_size = result_size + 1
      elseif b == 0x82 or b == 0xE3 then
        -- Problematic sequences
        table.insert(buffer, "?")
        result_size = result_size + 1
      else
        table.insert(buffer, string.char(b))
        result_size = result_size + 1
      end
      
      if result_size >= buffer_size then
        table.insert(result, table.concat(buffer))
        buffer = {}
        result_size = 0
      end
    end
    
    if result_size > 0 then
      table.insert(result, table.concat(buffer))
    end
    
    sanitized = table.concat(result)
    test_ok, _ = pcall(vim.fn.json_encode, { text = sanitized })
    if test_ok then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Text sanitized using table-based method")
      end
      if text_hash then
        sanitize_cache[text_hash] = sanitized
        table.insert(sanitize_cache_keys, text_hash)
      else
        sanitize_cache[text] = sanitized
        table.insert(sanitize_cache_keys, text)
      end
      return sanitized
    end
  end
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Using optimized chunk processing for text sanitization")
  end
  
  local chunk_size = 65536 -- 64KB chunks
  local result = {}
  local total_processed = 0
  
  while total_processed < #text do
    local chunk_end = math.min(total_processed + chunk_size, #text)
    local chunk = string.sub(text, total_processed + 1, chunk_end)
    
    local chunk_result = {}
    local i = 1
    
    while i <= #chunk do
      local b = string.byte(chunk, i)
      
      if b <= 31 or b == 127 then
        -- Skip control characters
        i = i + 1
      elseif b == 34 then -- double quote
        table.insert(chunk_result, '\\"')
        i = i + 1
      elseif b == 92 then -- backslash
        table.insert(chunk_result, '\\\\')
        i = i + 1
      -- Handle UTF-8 sequences efficiently
      elseif b >= 240 and b <= 247 then -- 4-byte sequence
        if i + 3 <= #chunk and 
           string.byte(chunk, i+1) >= 128 and string.byte(chunk, i+1) <= 191 and
           string.byte(chunk, i+2) >= 128 and string.byte(chunk, i+2) <= 191 and
           string.byte(chunk, i+3) >= 128 and string.byte(chunk, i+3) <= 191 then
          -- Valid 4-byte sequence - add as a single string
          table.insert(chunk_result, chunk:sub(i, i+3))
          i = i + 4
        else
          table.insert(chunk_result, "?")
          i = i + 1
        end
      elseif b >= 224 and b <= 239 then -- 3-byte sequence
        if i + 2 <= #chunk and 
           string.byte(chunk, i+1) >= 128 and string.byte(chunk, i+1) <= 191 and
           string.byte(chunk, i+2) >= 128 and string.byte(chunk, i+2) <= 191 then
          -- Valid 3-byte sequence
          table.insert(chunk_result, chunk:sub(i, i+2))
          i = i + 3
        else
          table.insert(chunk_result, "?")
          i = i + 1
        end
      elseif b >= 192 and b <= 223 then -- 2-byte sequence
        if i + 1 <= #chunk and 
           string.byte(chunk, i+1) >= 128 and string.byte(chunk, i+1) <= 191 then
          -- Valid 2-byte sequence
          table.insert(chunk_result, chunk:sub(i, i+1))
          i = i + 2
        else
          table.insert(chunk_result, "?")
          i = i + 1
        end
      -- Handle problematic byte sequences
      elseif b == 0x82 or b == 0xE3 then
        -- Special handling for problematic sequences
        table.insert(chunk_result, "?")
        i = i + 1
      elseif b >= 128 and b <= 191 then
        table.insert(chunk_result, "?")
        i = i + 1
      else
        -- ASCII character
        table.insert(chunk_result, chunk:sub(i, i))
        i = i + 1
      end
    end
    
    table.insert(result, table.concat(chunk_result))
    total_processed = chunk_end
  end
  
  local sanitized = table.concat(result)
  
  local final_ok, err = pcall(vim.fn.json_encode, { text = sanitized })
  if not final_ok then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] JSON encoding still failed, using ASCII-only fallback")
    end
    
    local ascii_result = {}
    local buffer = {}
    local buffer_size = 0
    local max_buffer = 1024
    
    for i = 1, #text do
      local b = string.byte(text, i)
      if b >= 32 and b <= 126 and b ~= 34 and b ~= 92 then
        table.insert(buffer, string.char(b))
        buffer_size = buffer_size + 1
      elseif b == 34 then -- double quote
        table.insert(buffer, '\\"')
        buffer_size = buffer_size + 1
      elseif b == 92 then -- backslash
        table.insert(buffer, '\\\\')
        buffer_size = buffer_size + 1
      elseif b == 10 or b == 13 or b == 9 then -- newline, carriage return, tab
        table.insert(buffer, string.char(b))
        buffer_size = buffer_size + 1
      else
        table.insert(buffer, "?")
        buffer_size = buffer_size + 1
      end
      
      if buffer_size >= max_buffer then
        table.insert(ascii_result, table.concat(buffer))
        buffer = {}
        buffer_size = 0
      end
    end
    
    if buffer_size > 0 then
      table.insert(ascii_result, table.concat(buffer))
    end
    
    sanitized = table.concat(ascii_result)
  end
  
  if #sanitize_cache_keys > MAX_CACHE_SIZE then
    local to_remove = #sanitize_cache_keys - MAX_CACHE_SIZE
    for i = 1, to_remove do
      local key = table.remove(sanitize_cache_keys, 1)
      sanitize_cache[key] = nil
    end
  end
  
  if text_hash then
    sanitize_cache[text_hash] = sanitized
    table.insert(sanitize_cache_keys, text_hash)
  else
    sanitize_cache[text] = sanitized
    table.insert(sanitize_cache_keys, text)
  end
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Text sanitization complete")
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

  -- Set up text change events to trigger notification timer
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

        local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        
        for _, filetype in ipairs(filetypes) do
          if not state.buf_content_by_filetype[buf] then
            state.buf_content_by_filetype[buf] = {}
          end
          state.buf_content_by_filetype[buf][filetype] = content
        end
        
        state.buf_content[buf] = content
        
        -- Start notification timer for API request
        M.start_notification_timer(buf, ctx.event)
      end, 100)
    end,
  })
  
  -- Set up cursor movement events to track cursor position and clear virtual text
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      M.clear_virtual_text(buf)
      
      -- Restart virtual text timer
      M.start_virtual_text_timer(buf, "CursorMoved")
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor moved in buffer %d, cleared virtual text and restarted timer", buf))
      end
      
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
      if log_file then
        log_file:write(string.format("Cursor moved in buffer %d at %s, cleared virtual text\n", 
          buf, os.date("%Y-%m-%d %H:%M:%S")))
        log_file:close()
      end
    end
  })
end

-- Stop notification timer for a buffer
function M.stop_notification_timer(buf)
  local timer_id = state.timers.notification[buf]
  if timer_id then
    vim.fn.timer_stop(timer_id)
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Stopped notification timer for buffer %d with ID %d", 
        buf, timer_id))
    end
    
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      log_file:write(string.format("Stopped notification timer for buffer %d with ID %d at %s\n", 
        buf, timer_id, os.date("%Y-%m-%d %H:%M:%S")))
      log_file:close()
    end
    
    local old_timer_id = timer_id
    state.timers.notification[buf] = nil
    return old_timer_id
  end
  return nil
end

-- Stop virtual text timer for a buffer
function M.stop_virtual_text_timer(buf)
  local timer_id = state.timers.virtual_text[buf]
  if timer_id then
    vim.fn.timer_stop(timer_id)
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Stopped virtual text timer for buffer %d with ID %d", 
        buf, timer_id))
    end
    
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      log_file:write(string.format("Stopped virtual text timer for buffer %d with ID %d at %s\n", 
        buf, timer_id, os.date("%Y-%m-%d %H:%M:%S")))
      log_file:close()
    end
    
    local old_timer_id = timer_id
    state.timers.virtual_text[buf] = nil
    return old_timer_id
  end
  return nil
end

-- Start notification timer for a buffer (for API requests)
function M.start_notification_timer(buf, event_name)
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
  
  -- Stop any existing notification timer
  M.stop_notification_timer(buf)
  
  local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
  if log_file then
    log_file:write("=== " .. event_name .. " triggered notification timer start at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    log_file:write("Buffer: " .. buf .. "\n")
    log_file:close()
  end
  
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 通知タイマー開始: バッファ %d, イベント %s", buf, event_name))
  end
  
  -- Create a new notification timer with execution_delay
  state.timers.notification[buf] = vim.fn.timer_start(config.execution_delay, function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    local content, diff, diff_filetype = get_buf_diff(buf)
    
    if not diff then
      return
    end
    
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
  end)
end

-- Start virtual text timer for a buffer (for display)
function M.start_virtual_text_timer(buf, event_name)
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
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Cannot start virtual text timer for invalid buffer %d", buf))
    end
    return
  end
  
  -- Stop any existing timer first
  M.stop_virtual_text_timer(buf)
  
  local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
  if log_file then
    local event_info = event_name and (" triggered by " .. event_name) or ""
    log_file:write("=== Virtual text timer start" .. event_info .. " at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    log_file:write("Buffer: " .. buf .. "\n")
    log_file:close()
  end
  
  if config.debug_mode then
    local event_str = event_name or "unknown"
    print(string.format("[Nudge Two Hats Debug] virtual textタイマー開始: バッファ %d, イベント %s", buf, event_str))
  end
  
  -- Calculate timer duration in milliseconds
  local timer_ms = config.virtual_text.idle_time * 60 * 1000
  
  -- Create a new timer
  state.timers.virtual_text[buf] = vim.fn.timer_start(timer_ms, function()
    -- Check if buffer is still valid
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop_virtual_text_timer(buf)
      return
    end
    
    -- Check if we have advice to display
    if not state.virtual_text.last_advice[buf] then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] No advice available for buffer %d", buf))
      end
      return
    end
    
    -- Check if cursor has been idle long enough
    local current_time = os.time()
    local last_cursor_move_time = state.virtual_text.last_cursor_move[buf] or 0
    local idle_time = current_time - last_cursor_move_time
    local required_idle_time = (config.virtual_text.cursor_idle_delay or 5) * 60
    
    if idle_time >= required_idle_time then
      M.display_virtual_text(buf, state.virtual_text.last_advice[buf])
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Displaying virtual text for buffer %d after %d seconds of cursor inactivity", 
          buf, idle_time))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor not idle long enough: %d seconds (required: %d seconds)", 
          idle_time, required_idle_time))
      end
      
      M.start_virtual_text_timer(buf)
    end
  end)
  
  if config.debug_mode then
    local event_info = event_name and (" triggered by " .. event_name) or ""
    print(string.format("[Nudge Two Hats Debug] Started virtual text timer for buffer %d with ID %d%s", 
      buf, state.timers.virtual_text[buf], event_info))
  end
  
  local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
  if log_file then
    local event_info = event_name and (" triggered by " .. event_name) or ""
    log_file:write(string.format("Started virtual text timer for buffer %d with ID %d%s at %s\n", 
      buf, state.timers.virtual_text[buf], event_info, os.date("%Y-%m-%d %H:%M:%S")))
    log_file:close()
  end
  
  return state.timers.virtual_text[buf]
end

local function start_notification_timer(buf, event_name)
  M.start_notification_timer(buf, event_name)
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

function M.stop_notification_timer(buf)
  if state.timers.notification[buf] then
    local timer_id = state.timers.notification[buf]
    vim.fn.timer_stop(timer_id)
    state.timers.notification[buf] = nil
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 通知タイマー停止: バッファ %d, タイマーID %d", buf, timer_id))
    end
    
    return timer_id
  end
  
  return nil
end

function M.stop_virtual_text_timer(buf)
  if state.timers.virtual_text[buf] then
    local timer_id = state.timers.virtual_text[buf]
    vim.fn.timer_stop(timer_id)
    state.timers.virtual_text[buf] = nil
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] virtual textタイマー停止: バッファ %d, タイマーID %d", buf, timer_id))
    end
    
    return timer_id
  end
  
  return nil
end

function M.stop_timer(buf)
  local notification_timer_id = M.stop_notification_timer(buf)
  local virtual_text_timer_id = M.stop_virtual_text_timer(buf)
  
  return notification_timer_id or virtual_text_timer_id
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
      
      for buf, timer_id in pairs(state.timers.notification) do
        if timer_id then
          vim.fn.timer_stop(timer_id)
          state.timers.notification[buf] = nil
          
          if log_file then
            log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
            if log_file then
              log_file:write("Stopping notification timer with ID: " .. timer_id .. " when disabling plugin\n")
              log_file:close()
            end
          end
        end
      end
      
      for buf, timer_id in pairs(state.timers.virtual_text) do
        if timer_id then
          vim.fn.timer_stop(timer_id)
          state.timers.virtual_text[buf] = nil
          
          if log_file then
            log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
            if log_file then
              log_file:write("Stopping virtual text timer with ID: " .. timer_id .. " when disabling plugin\n")
              log_file:close()
            end
          end
        end
      end
      
      for buf, timer_id in pairs(state.virtual_text.timers) do
        if timer_id then
          vim.fn.timer_stop(timer_id)
          state.virtual_text.timers[buf] = nil
          
          if log_file then
            log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
            if log_file then
              log_file:write("Stopping legacy timer with ID: " .. timer_id .. " when disabling plugin\n")
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
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugTimerStatus", function()
    print("========== Nudge Two Hats Timer Status ==========")
    print("Plugin enabled: " .. tostring(state.enabled))
    
    local active_notification_timers = 0
    local active_virtual_text_timers = 0
    local inactive_buffers = 0
    
    state.timers = state.timers or {
      notification = {},
      virtual_text = {}
    }
    
    for buf, _ in pairs(state.buf_filetypes) do
      if vim.api.nvim_buf_is_valid(buf) then
        local filetypes = state.buf_filetypes[buf] or ""
        local notification_timer_id = state.timers.notification[buf]
        local virtual_text_timer_id = state.timers.virtual_text[buf]
        local legacy_timer_id = (state.virtual_text.timers and state.virtual_text.timers[buf])
        
        print(string.format("\nバッファ: %d, Filetype: %s", buf, filetypes))
        
        -- Check notification timer
        if notification_timer_id then
          active_notification_timers = active_notification_timers + 1
          local timer_info = vim.fn.timer_info(notification_timer_id)
          local remaining = "不明"
          
          if timer_info and #timer_info > 0 then
            local time_ms = timer_info[1].time
            if time_ms > 60000 then
              remaining = string.format("%.1f分", time_ms / 60000)
            else
              remaining = string.format("%.1f秒", time_ms / 1000)
            end
          end
          
          print(string.format("  通知タイマー: ID = %d, 残り時間: %s", 
                             notification_timer_id, remaining))
        end
        
        -- Check virtual text timer
        if virtual_text_timer_id then
          active_virtual_text_timers = active_virtual_text_timers + 1
          local timer_info = vim.fn.timer_info(virtual_text_timer_id)
          local remaining = "不明"
          
          if timer_info and #timer_info > 0 then
            local time_ms = timer_info[1].time
            if time_ms > 60000 then
              remaining = string.format("%.1f分", time_ms / 60000)
            else
              remaining = string.format("%.1f秒", time_ms / 1000)
            end
          end
          
          print(string.format("  Virtual Textタイマー: ID = %d, 残り時間: %s", 
                             virtual_text_timer_id, remaining))
        end
        
        -- Check legacy timer (for backward compatibility)
        if legacy_timer_id then
          local timer_info = vim.fn.timer_info(legacy_timer_id)
          local remaining = "不明"
          
          if timer_info and #timer_info > 0 then
            local time_ms = timer_info[1].time
            if time_ms > 60000 then
              remaining = string.format("%.1f分", time_ms / 60000)
            else
              remaining = string.format("%.1f秒", time_ms / 1000)
            end
          end
          
          print(string.format("  レガシータイマー: ID = %d, 残り時間: %s", 
                             legacy_timer_id, remaining))
        end
        
        if not notification_timer_id and not virtual_text_timer_id and not legacy_timer_id then
          inactive_buffers = inactive_buffers + 1
          print("  アクティブなタイマーなし")
        end
      end
    end
    
    print(string.format("\n合計: 通知タイマー = %d, Virtual Textタイマー = %d, 非アクティブなバッファ = %d", 
                       active_notification_timers, active_virtual_text_timers, inactive_buffers))
    print("==========================================")
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsNow", function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    local line_count = vim.api.nvim_buf_line_count(buf)
    local current_content
    
    if line_count < 1000 then
      current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    else
      local chunks = {}
      local chunk_size = 500
      local total_chunks = math.ceil(line_count / chunk_size)
      
      for i = 0, total_chunks - 1 do
        local start_line = i * chunk_size
        local end_line = math.min((i + 1) * chunk_size, line_count)
        table.insert(chunks, table.concat(vim.api.nvim_buf_get_lines(buf, start_line, end_line, false), "\n"))
      end
      
      current_content = table.concat(chunks, "\n")
    end
    
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
    
    local stored_content = {}
    local stored_content_by_filetype = {}
    
    if state.buf_content[buf] then
      stored_content = state.buf_content[buf]
      state.buf_content[buf] = nil
    end
    
    if state.buf_content_by_filetype[buf] then
      stored_content_by_filetype = state.buf_content_by_filetype[buf]
      state.buf_content_by_filetype[buf] = {}
    end
    
    local content, diff, diff_filetype = get_buf_diff(buf)
    
    if not diff then
      diff = "@@ -0,0 +1," .. #vim.api.nvim_buf_get_lines(buf, 0, -1, false) .. " @@\n"
        .. "+ " .. current_content
      diff_filetype = filetypes[1]
      
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Created forced diff for NudgeTwoHatsNow command")
      end
    end
    
    -- Restore original stored content after diff generation
    state.buf_content[buf] = stored_content
    state.buf_content_by_filetype[buf] = stored_content_by_filetype
    
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
        
        if state.buf_filetypes[buf] then
          -- Start virtual text timer for displaying advice
          M.start_virtual_text_timer(buf)
          
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] BufEnter: Restarted virtual text timer for buffer %d", buf))
          end
        end
      end
    end
  })
  
  vim.api.nvim_create_autocmd("BufLeave", {
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      
      -- Stop notification timer
      local notification_timer_id = M.stop_notification_timer(buf)
      
      -- Stop virtual text timer
      local virtual_text_timer_id = M.stop_virtual_text_timer(buf)
      
      if notification_timer_id or virtual_text_timer_id then
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== BufLeave triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:write("Leaving buffer: " .. buf .. "\n")
          if notification_timer_id then
            log_file:write("Stopped notification timer: " .. notification_timer_id .. "\n")
          end
          if virtual_text_timer_id then
            log_file:write("Stopped virtual text timer: " .. virtual_text_timer_id .. "\n")
          end
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
