local config = require("nudge-two-hats.config")

-- Get advice_cache and translations from the caller
local advice_cache = {}
local MAX_ADVICE_CACHE_SIZE = 20
local advice_cache_keys = {}

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

-- Cache for sanitized text
local sanitize_cache = {}
local sanitize_cache_keys = {}
local MAX_CACHE_SIZE = 20

-- Sanitize text for API requests
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
    -- Use individual character replacements to avoid pattern issues with multibyte characters
    local sanitized = ""
    for i = 1, #text do
      local c = text:sub(i, i)
      local b = string.byte(c)
      if b < 32 or b == 127 then
        -- Skip control characters
      elseif b == 92 then -- backslash
        sanitized = sanitized .. "\\\\"
      elseif b == 34 then -- double quote
        sanitized = sanitized .. "\\\""
      elseif b == 192 or b == 193 then -- Invalid UTF-8 lead bytes
        sanitized = sanitized .. "?"
      elseif b >= 245 and b <= 255 then -- Invalid UTF-8 lead bytes
        sanitized = sanitized .. "?"
      else
        sanitized = sanitized .. c
      end
    end
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

-- Check if text contains Japanese characters
local function is_japanese(text)
  return text:match("[\227-\233]") ~= nil
end

-- Translate text using Gemini API
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
  -- Delete the temporary file after API call
  if vim.fn.filereadable(temp_file) == 1 then
    vim.fn.delete(temp_file)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Deleted temporary file: " .. temp_file)
    end
  end
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

-- Translate messages based on config settings
local function translate_message(message)
  if not config.translate_messages then
    return message
  end
  local target_lang = get_language()
  for key, value in pairs(config.translations[target_lang]) do
    if message == value then
      return message -- Already in target language
    end
  end
  for key, value in pairs(config.translations.en) do
    if message == value and config.translations[target_lang][key] then
      return config.translations[target_lang][key]
    end
  end
  for key, value in pairs(config.translations.ja) do
    if message == value and config.translations[target_lang][key] then
      return config.translations[target_lang][key]
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

-- Get advice from Gemini API
local function get_gemini_advice(diff, callback, prompt, purpose, state)
  local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] API Key: %s", api_key and "設定済み" or "未設定"))
  end
  if not api_key then
    local error_msg = translate_message(config.translations.en.api_key_not_set)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] APIキーが設定されていません")
    end
    vim.notify(error_msg, vim.log.levels.ERROR)
    return
  end

  local cache_key = nil
  if #diff < 10000 then  -- Only cache for reasonably sized diffs
    cache_key = diff .. (prompt or "") .. (purpose or "")
    -- Check if we have a cached response
    if advice_cache[cache_key] then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Using cached API response")
      end
      vim.schedule(function()
        callback(advice_cache[cache_key])
      end)
      return
    end
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
  print(system_prompt)
  local max_diff_size = 10000  -- 10KB is usually enough for context
  local truncated_diff = diff
  if #diff > max_diff_size then
    truncated_diff = string.sub(diff, 1, max_diff_size) .. "\n... (truncated for performance)"
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Diff truncated from " .. #diff .. " to " .. #truncated_diff .. " bytes")
    end
  end
  local sanitized_diff = sanitize_text(truncated_diff)
  if config.debug_mode and sanitized_diff ~= truncated_diff then
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
    local error_msg = translate_message(config.translations.en.api_error)
    vim.notify(error_msg .. ": JSON encoding failed", vim.log.levels.ERROR)
    callback(translate_message(config.translations.en.api_error))
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
              if cache_key then
                advice_cache[cache_key] = advice
                table.insert(advice_cache_keys, cache_key)
                if #advice_cache_keys > MAX_ADVICE_CACHE_SIZE then
                  local to_remove = table.remove(advice_cache_keys, 1)
                  advice_cache[to_remove] = nil
                end
              end
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
            else
              callback(translate_message(config.translations.en.api_error))
            end
          else
            local error_msg = translate_message(config.translations.en.api_error)
            vim.notify(error_msg .. ": " .. (response.body or translate_message(config.translations.en.unknown_error)), vim.log.levels.ERROR)
            callback(translate_message(config.translations.en.api_error))
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
              
            else
              callback(translate_message(config.translations.en.api_error))
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
            
            local error_msg = translate_message(config.translations.en.api_error)
            vim.notify(error_msg .. ": " .. table.concat(data, "\n"), vim.log.levels.ERROR)
          end)
        end
      end,
      on_exit = function(_, code)
        -- Delete the temporary file after API call completes
        if vim.fn.filereadable(temp_file) == 1 then
          vim.fn.delete(temp_file)
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Deleted temporary file: " .. temp_file)
          end
        end
        if code ~= 0 then
          vim.schedule(function()
            callback(translate_message(config.translations.en.api_error))
          end)
        end
      end
    })
  end
end

-- Export the functions with state management
local M = {
  is_japanese = is_japanese,
  translate_with_gemini = translate_with_gemini,
  sanitize_text = sanitize_text,
  safe_truncate = safe_truncate,
  get_language = get_language,
  translate_message = translate_message
}

-- Wrap get_gemini_advice to handle different call patterns from init.lua
function M.get_gemini_advice(diff, callback, arg1, arg2, arg3)
  -- 引数の型に基づいて振り分ける
  -- init.luaからの呼び出しパターン
  -- 1. api.get_gemini_advice(diff, function(advice)
  -- 2. api.get_gemini_advice(diff, function(advice), state
  -- 3. api.get_gemini_advice(diff, function(advice), nil, nil, state
  local prompt, purpose, state
  
  if type(arg1) == "table" then 
    -- パターン2: arg1がstateオブジェクト
    state = arg1
    prompt = nil
    purpose = nil
  elseif type(arg1) == "string" then
    -- arg1がプロンプト文字列
    prompt = arg1
    if type(arg2) == "string" then
      purpose = arg2
      state = arg3
    else
      purpose = nil
      state = arg2
    end
  elseif arg1 == nil and arg2 == nil and type(arg3) == "table" then
    -- パターン3: nil, nil, state
    prompt = nil
    purpose = nil
    state = arg3
  else
    -- デフォルト
    prompt = arg1
    purpose = arg2
    state = arg3 or {}
  end
  
  -- stateがない場合は空のテーブルを使用
  state = state or {}
  return get_gemini_advice(diff, callback, prompt, purpose, state)
end

return M
