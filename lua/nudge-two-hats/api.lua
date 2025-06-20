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

-- Helper function to check if text is ASCII-only
local function is_text_ascii_only(text)
  local check_limit = math.min(100, #text)
  for i = 1, check_limit do
    local b = string.byte(text, i)
    if b >= 128 or b <= 31 or b == 34 or b == 92 or b == 127 then
      return false
    end
  end

  if #text > 100 then
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
        return false
      end
    end
  end
  return true
end

-- Helper function to sanitize character
local function sanitize_char(b)
  if b < 32 or b == 127 then
    return "" -- Skip control characters
  elseif b == 92 then -- backslash
    return "\\\\"
  elseif b == 34 then -- double quote
    return "\\\""
  elseif b == 192 or b == 193 or (b >= 245 and b <= 255) then
    return "?" -- Invalid UTF-8 lead bytes
  else
    return string.char(b)
  end
end

-- Helper function for small text sanitization
local function sanitize_small_text(text)
  local sanitized = ""
  for i = 1, #text do
    local b = string.byte(text, i)
    sanitized = sanitized .. sanitize_char(b)
  end
  return sanitized
end

-- Helper function for UTF-8 chunk processing
local function process_utf8_chunk(chunk)
  local chunk_result = {}
  local i = 1

  while i <= #chunk do
    local b = string.byte(chunk, i)

    if b <= 31 or b == 127 then
      i = i + 1 -- Skip control characters
    elseif b == 34 then -- double quote
      table.insert(chunk_result, '\\"')
      i = i + 1
    elseif b == 92 then -- backslash
      table.insert(chunk_result, '\\\\')
      i = i + 1
    elseif b >= 240 and b <= 247 then -- 4-byte sequence
      if i + 3 <= #chunk and
         string.byte(chunk, i+1) >= 128 and string.byte(chunk, i+1) <= 191 and
         string.byte(chunk, i+2) >= 128 and string.byte(chunk, i+2) <= 191 and
         string.byte(chunk, i+3) >= 128 and string.byte(chunk, i+3) <= 191 then
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
        table.insert(chunk_result, chunk:sub(i, i+2))
        i = i + 3
      else
        table.insert(chunk_result, "?")
        i = i + 1
      end
    elseif b >= 192 and b <= 223 then -- 2-byte sequence
      if i + 1 <= #chunk and
         string.byte(chunk, i+1) >= 128 and string.byte(chunk, i+1) <= 191 then
        table.insert(chunk_result, chunk:sub(i, i+1))
        i = i + 2
      else
        table.insert(chunk_result, "?")
        i = i + 1
      end
    else
      table.insert(chunk_result, chunk:sub(i, i))
      i = i + 1
    end
  end

  return table.concat(chunk_result)
end

-- Helper function to update cache
local function update_sanitize_cache(key, value)
  if #sanitize_cache_keys > MAX_CACHE_SIZE then
    local to_remove = #sanitize_cache_keys - MAX_CACHE_SIZE
    for i = 1, to_remove do
      local old_key = table.remove(sanitize_cache_keys, 1)
      sanitize_cache[old_key] = nil
    end
  end

  sanitize_cache[key] = value
  table.insert(sanitize_cache_keys, key)
end

-- Main sanitization function (simplified)
local function sanitize_text(text, state)
  if not text then
    return ""
  end

  if config.debug_mode then
    print("[Nudge Two Hats Debug] sanitize_text: Input text length: " .. #text)
    if state then
      print("[Nudge Two Hats Debug] Context for: " .. (state.context_for or "unknown"))
    end
  end

  -- Check cache first
  if sanitize_cache[text] then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using cached sanitized text")
    end
    return sanitize_cache[text]
  end

  -- Handle large text with hash-based caching
  local cache_key = text
  if #text > 1024 then
    local text_hash = 0
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
    cache_key = text_hash
  end

  -- Check if text is ASCII-only
  if is_text_ascii_only(text) then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Text is ASCII-only, no sanitization needed")
    end
    update_sanitize_cache(cache_key, text)
    return text
  end

  local sanitized

  -- Small text: use simple character-by-character processing
  if #text < 10240 then
    sanitized = sanitize_small_text(text)
    local test_ok = pcall(vim.fn.json_encode, { text = sanitized })
    if test_ok then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Text sanitized using fast method")
      end
      update_sanitize_cache(cache_key, sanitized)
      return sanitized
    end
  end

  -- Large text: use chunk processing
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Using optimized chunk processing for text sanitization")
  end

  local chunk_size = 65536
  local result = {}
  local total_processed = 0

  while total_processed < #text do
    local chunk_end = math.min(total_processed + chunk_size, #text)
    local chunk = string.sub(text, total_processed + 1, chunk_end)
    table.insert(result, process_utf8_chunk(chunk))
    total_processed = chunk_end
  end

  sanitized = table.concat(result)

  -- Final validation and ASCII fallback if needed
  local final_ok = pcall(vim.fn.json_encode, { text = sanitized })
  if not final_ok then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] JSON encoding failed, using ASCII-only fallback")
    end
    sanitized = sanitize_small_text(text):gsub("[^%w%s%p]", "?")
  end

  update_sanitize_cache(cache_key, sanitized)

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
      print("[Nudge Two Hats Debug] Error: " .. error_msg)
    else
      vim.notify(error_msg, vim.log.levels.ERROR)
    end
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

  -- Check for previous notification message to avoid duplicates
  local context_for = state.context_for or "notification"
  local current_buf = vim.api.nvim_get_current_buf()
  local previous_message = nil

  if context_for == "notification" and state.notifications and state.notifications.last_advice then
    previous_message = state.notifications.last_advice[current_buf]
  elseif context_for == "virtual_text" and state.virtual_text and state.virtual_text.last_advice then
    previous_message = state.virtual_text.last_advice[current_buf]
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

  local context_for = state.context_for or "notification" -- Ensure context_for is defined before use
  local system_prompt = prompt or state.current_prompt
  if not system_prompt then
    -- If no prompt is provided, use the system prompt as fallback (this should not happen with proper usage)
    system_prompt = config[context_for].system_prompt
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Warning: Using config system_prompt as fallback. This may indicate an issue with prompt generation.")
    end
  end
  local purpose_text = purpose or state.current_purpose or config[context_for].purpose
  if purpose_text and purpose_text ~= "" then
    system_prompt = system_prompt .. "\n\nWork purpose: " .. purpose_text
  end
  local output_lang = get_language()

  -- Add anti-duplication instruction if previous message exists
  local anti_duplication_prompt = ""
  if previous_message and previous_message ~= "" then
    if output_lang == "ja" then
      anti_duplication_prompt = string.format("\n重要: 前回のメッセージ「%s」と全く同じ内容は避け、必ず異なる視点や表現でアドバイスしてください。", previous_message)
    else
      anti_duplication_prompt = string.format("\nIMPORTANT: Avoid repeating the exact same content as the previous message: \"%s\". Provide advice from a different perspective or with different wording.", previous_message)
    end
  end

  if output_lang == "ja" then
    if context_for == "notification" then
      system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。通知用に%d文字以内で簡潔かつ完結したアドバイスをお願いします。文章は途中で切れないようにしてください。%s", config[context_for].notify_message_length, anti_duplication_prompt)
    else
      system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。仮想テキスト用に%d文字以内で簡潔かつ完結したアドバイスをお願いします。文章は途中で切れないようにしてください。%s", config[context_for].virtual_text_message_length, anti_duplication_prompt)
    end
  else
    if context_for == "notification" then
      system_prompt = system_prompt .. string.format("\nPlease respond in English. For notifications, provide concise and complete advice within %d characters. Ensure the message is meaningful and not cut off mid-sentence.%s", config[context_for].notify_message_length, anti_duplication_prompt)
    else
      system_prompt = system_prompt .. string.format("\nPlease respond in English. For virtual text, provide concise and complete advice within %d characters. Ensure the message is meaningful and not cut off mid-sentence.%s", config[context_for].virtual_text_message_length, anti_duplication_prompt)
    end
  end
  -- print(system_prompt)
  local max_diff_size = 10000  -- 10KB is usually enough for context
  local truncated_diff = diff
  if #diff > max_diff_size then
    truncated_diff = string.sub(diff, 1, max_diff_size) .. "\n... (truncated for performance)"
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Diff truncated from " .. #diff .. " to " .. #truncated_diff .. " bytes")
    end
  end
  local sanitized_diff = sanitize_text(truncated_diff, state)
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
        thinkingBudget = 0,
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
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Error: " .. error_msg .. ": JSON encoding failed")
    else
      vim.notify(error_msg .. ": JSON encoding failed", vim.log.levels.ERROR)
    end
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

              -- Check if the new advice is identical to the previous message
              if previous_message and advice == previous_message then
                if config.debug_mode then
                  print("[Nudge Two Hats Debug] Identical message detected, requesting retry...")
                end
                -- Request a different response by modifying the prompt
                local retry_prompt = system_prompt
                if output_lang == "ja" then
                  retry_prompt = retry_prompt .. "\n追加指示: 前回と全く同じ回答でした。必ず異なる内容で再度アドバイスしてください。"
                else
                  retry_prompt = retry_prompt .. "\nAdditional instruction: The previous response was identical. Please provide a completely different advice."
                end

                -- Make a retry API call with modified prompt
                local retry_request_data = vim.fn.json_encode({
                  contents = {
                    {
                      parts = {
                        {
                          text = retry_prompt .. "\n\n" .. sanitized_diff
                        }
                      }
                    }
                  },
                  generationConfig = {
                    thinkingConfig = {
                      thinkingBudget = 0,
                    },
                    temperature = 0.7, -- Increase temperature for more variation
                    topK = 60,
                    topP = 0.9,
                    maxOutputTokens = 1024
                  }
                })

                -- Use curl for immediate retry
                local temp_retry_file = "/tmp/nudge_two_hats_retry.json"
                local retry_file = io.open(temp_retry_file, "w")
                if retry_file then
                  retry_file:write(retry_request_data)
                  retry_file:close()
                end

                local endpoint = config.api_endpoint:gsub("[<>]", "")
                local full_url = endpoint .. "?key=" .. api_key
                local retry_command = string.format("curl -s -X POST %s -H 'Content-Type: application/json' -d @%s", full_url, temp_retry_file)

                vim.fn.jobstart(retry_command, {
                  on_stdout = function(_, retry_data)
                    if retry_data and #retry_data > 0 and retry_data[1] ~= "" then
                      vim.schedule(function()
                        local retry_ok, retry_response = pcall(vim.json.decode, table.concat(retry_data, "\n"))
                        if retry_ok and retry_response and retry_response.candidates and retry_response.candidates[1] and
                           retry_response.candidates[1].content and retry_response.candidates[1].content.parts and
                           retry_response.candidates[1].content.parts[1] and retry_response.candidates[1].content.parts[1].text then
                          local retry_advice = retry_response.candidates[1].content.parts[1].text

                          -- Apply length limits to retry advice
                          local message_length = config[context_for].notify_message_length
                          if context_for == "virtual_text" then
                            message_length = config[context_for].virtual_text_message_length
                          end
                          if config.length_type == "characters" then
                            if #retry_advice > message_length then
                              retry_advice = safe_truncate(retry_advice, message_length)
                            end
                          else
                            local words = {}
                            for word in retry_advice:gmatch("%S+") do
                              table.insert(words, word)
                            end
                            if #words > message_length then
                              local truncated_words = {}
                              for i = 1, message_length do
                                table.insert(truncated_words, words[i])
                              end
                              retry_advice = table.concat(truncated_words, " ")
                            end
                          end
                          if config.translate_messages then
                            retry_advice = translate_message(retry_advice)
                          end

                          if config.debug_mode then
                            print("[Nudge Two Hats Debug] Retry successful, using different advice")
                          end
                          callback(retry_advice)
                        else
                          -- If retry fails, use original advice anyway
                          if config.debug_mode then
                            print("[Nudge Two Hats Debug] Retry failed, using original advice")
                          end
                          callback(advice)
                        end
                      end)
                    end
                  end,
                  on_exit = function()
                    if vim.fn.filereadable(temp_retry_file) == 1 then
                      vim.fn.delete(temp_retry_file)
                    end
                  end
                })
                return -- Don't continue with the original response processing
              end

              if cache_key then
                advice_cache[cache_key] = advice
                table.insert(advice_cache_keys, cache_key)
                if #advice_cache_keys > MAX_ADVICE_CACHE_SIZE then
                  local to_remove = table.remove(advice_cache_keys, 1)
                  advice_cache[to_remove] = nil
                end
              end
              local message_length = config[context_for].notify_message_length
              if context_for == "virtual_text" then
                message_length = config[context_for].virtual_text_message_length
              end
              if config.length_type == "characters" then
                if #advice > message_length then
                  advice = safe_truncate(advice, message_length)
                end
              else
                local words = {}
                for word in advice:gmatch("%S+") do
                  table.insert(words, word)
                end
                if #words > message_length then
                  local truncated_words = {}
                  for i = 1, message_length do
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
            local full_error = error_msg .. ": " .. (response.body or translate_message(config.translations.en.unknown_error))
            if config.debug_mode then
              print("[Nudge Two Hats Debug] Error: " .. full_error)
            else
              vim.notify(full_error, vim.log.levels.ERROR)
            end
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

              -- Check if the new advice is identical to the previous message (curl fallback)
              if previous_message and advice == previous_message then
                if config.debug_mode then
                  print("[Nudge Two Hats Debug] Identical message detected in curl fallback, using temperature variation...")
                end
                -- For curl fallback, we'll modify the advice slightly rather than making another API call
                local suffix_variations = {
                  ja = {" (改善案)", " (別のアプローチ)", " (追加提案)", " (代替案)", " (補足)"},
                  en = {" (Alternative)", " (Improvement)", " (Additional)", " (Variant)", " (Supplement)"}
                }
                local variations = suffix_variations[output_lang] or suffix_variations.en
                local random_suffix = variations[math.random(#variations)]
                advice = advice .. random_suffix
              end

              local message_length = config[context_for].notify_message_length
              if context_for == "virtual_text" then
                message_length = config[context_for].virtual_text_message_length
              end
              if config.length_type == "characters" then
                if #advice > message_length then
                  advice = safe_truncate(advice, message_length)
                end
              else
                local words = {}
                for word in advice:gmatch("%S+") do
                  table.insert(words, word)
                end
                if #words > message_length then
                  local truncated_words = {}
                  for i = 1, message_length do
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
            local full_error = error_msg .. ": " .. table.concat(data, "\n")
            if config.debug_mode then
              print("[Nudge Two Hats Debug] Error: " .. full_error)
            else
              vim.notify(full_error, vim.log.levels.ERROR)
            end
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

function M.update_config(new_config)
  config = new_config
end

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
