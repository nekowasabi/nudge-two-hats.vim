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

local function normalize_non_empty_string(value)
  if type(value) ~= "string" then
    return nil
  end
  if value == "" then
    return nil
  end
  return value
end

local function get_openrouter_base_url()
  local base_url = normalize_non_empty_string(config.openrouter_base_url) or "https://openrouter.ai/api/v1"
  return base_url:gsub("/+$", "")
end

local function get_openrouter_model()
  return normalize_non_empty_string(config.openrouter_model)
end

local function get_openrouter_api_key(state)
  local env_value = nil
  if vim.env then
    env_value = vim.env.OPENROUTER_API_KEY
  end
  if not env_value and vim.fn and vim.fn.getenv then
    env_value = vim.fn.getenv("OPENROUTER_API_KEY")
  end
  local env_key = normalize_non_empty_string(env_value)
  if env_key then
    return env_key
  end
  if state then
    return normalize_non_empty_string(state.api_key)
  end
  return nil
end

local function mask_secret(secret)
  if type(secret) ~= "string" then
    return "(invalid)"
  end
  if #secret <= 5 then
    return secret
  end
  return string.sub(secret, 1, 5) .. "..."
end

local function build_openrouter_headers(api_key)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. api_key,
  }
  local site_url = normalize_non_empty_string(config.openrouter_site_url)
  local app_name = normalize_non_empty_string(config.openrouter_app_name)
  if site_url then
    headers["HTTP-Referer"] = site_url
  end
  if app_name then
    headers["X-Title"] = app_name
  end
  return headers
end

local function append_provider_preference(request_obj)
  local provider = normalize_non_empty_string(config.openrouter_provider)
  if provider then
    request_obj.provider = {
      order = { provider }
    }
  end
end

local function extract_openrouter_message(response_obj)
  if not (response_obj and response_obj.choices and response_obj.choices[1] and response_obj.choices[1].message) then
    return nil
  end

  local content = response_obj.choices[1].message.content
  if type(content) == "string" then
    return content
  end

  if type(content) == "table" then
    local chunks = {}
    for _, part in ipairs(content) do
      if type(part) == "string" then
        table.insert(chunks, part)
      elseif type(part) == "table" and type(part.text) == "string" then
        table.insert(chunks, part.text)
      end
    end
    if #chunks > 0 then
      return table.concat(chunks)
    end
  end

  return nil
end

local function build_openrouter_request(model, system_prompt, user_content, temperature)
  local request_obj = {
    model = model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = user_content },
    },
    temperature = temperature,
    max_tokens = 1024,
  }
  append_provider_preference(request_obj)
  return request_obj
end

local function build_curl_command(url, temp_file, api_key)
  local args = {
    "curl -s -X POST",
    vim.fn.shellescape(url),
    "-H " .. vim.fn.shellescape("Content-Type: application/json"),
    "-H " .. vim.fn.shellescape("Authorization: Bearer " .. api_key),
  }

  local site_url = normalize_non_empty_string(config.openrouter_site_url)
  local app_name = normalize_non_empty_string(config.openrouter_app_name)
  if site_url then
    table.insert(args, "-H " .. vim.fn.shellescape("HTTP-Referer: " .. site_url))
  end
  if app_name then
    table.insert(args, "-H " .. vim.fn.shellescape("X-Title: " .. app_name))
  end

  table.insert(args, "-d @" .. vim.fn.shellescape(temp_file))
  return table.concat(args, " ")
end

local function make_temp_json_path(prefix)
  if vim.fn and vim.fn.tempname then
    local ok, tempname = pcall(vim.fn.tempname)
    if ok and type(tempname) == "string" and tempname ~= "" then
      return tempname .. "_" .. prefix .. ".json"
    end
  end
  return string.format("/tmp/nudge_two_hats_%s_%d_%d.json", prefix, os.time(), math.random(100000, 999999))
end

local function apply_message_length_limit(advice, context_for)
  local context_settings = config[context_for] or config.notification or {}
  local message_length = context_settings.notify_message_length or 80
  if context_for == "virtual_text" then
    message_length = context_settings.virtual_text_message_length or message_length
  end

  if config.length_type == "characters" then
    if #advice > message_length then
      return safe_truncate(advice, message_length)
    end
    return advice
  end

  local words = {}
  for word in advice:gmatch("%S+") do
    table.insert(words, word)
  end
  if #words > message_length then
    local truncated_words = {}
    for i = 1, message_length do
      table.insert(truncated_words, words[i])
    end
    return table.concat(truncated_words, " ")
  end
  return advice
end

-- Translate text using OpenRouter API
local function translate_with_openrouter(text, source_lang, target_lang, api_key, model)
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Translating: " .. text)
  end

  local normalized_api_key = normalize_non_empty_string(api_key)
  local normalized_model = normalize_non_empty_string(model) or get_openrouter_model()
  if not normalized_api_key or not normalized_model then
    return nil
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

  local request_obj = build_openrouter_request(
    normalized_model,
    "You are a concise translator. Preserve meaning and keep output short.",
    prompt,
    0.1
  )
  request_obj.max_tokens = 256

  local ok, request_data = pcall(vim.fn.json_encode, request_obj)
  if not ok then
    return nil
  end

  local full_url = get_openrouter_base_url() .. "/chat/completions"
  local temp_file = make_temp_json_path("translation")
  local req_file = io.open(temp_file, "w")
  if not req_file then
    return nil
  end
  req_file:write(request_data)
  req_file:close()

  local output = vim.fn.system(build_curl_command(full_url, temp_file, normalized_api_key))
  if vim.fn.filereadable(temp_file) == 1 then
    vim.fn.delete(temp_file)
  end

  local decode_ok, response
  if vim.json and vim.json.decode then
    decode_ok, response = pcall(vim.json.decode, output)
  else
    decode_ok, response = pcall(function() return vim.fn.json_decode(output) end)
  end
  if not decode_ok then
    return nil
  end
  return extract_openrouter_message(response)
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
  local api_key = get_openrouter_api_key(nil)
  local model = get_openrouter_model()
  if config.translate_messages and api_key and model and target_lang ~= "en" and not is_japanese(message) then
    if target_lang == "ja" and message:len() < 100 then
      local translated = translate_with_openrouter(message, "en", "ja", api_key, model)
      if translated then
        return translated
      end
    end
  elseif config.translate_messages and api_key and model and target_lang ~= "ja" and is_japanese(message) then
    if target_lang == "en" and message:len() < 100 then
      local translated = translate_with_openrouter(message, "ja", "en", api_key, model)
      if translated then
        return translated
      end
    end
  end
  return message
end

-- Get advice from OpenRouter API
local function get_openrouter_advice(diff, callback, prompt, purpose, state)
  if type(callback) ~= "function" then
    return
  end

  state = state or {}

  local api_key = get_openrouter_api_key(state)
  local model = get_openrouter_model()
  local default_api_key_error = (config.translations.en and config.translations.en.api_key_not_set) or "OPENROUTER_API_KEY is not set"
  local default_model_error = (config.translations.en and config.translations.en.model_not_set) or "OpenRouter model is not set"
  local api_key_error_msg = translate_message(default_api_key_error)
  local model_error_msg = translate_message(default_model_error)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] OpenRouter API Key: %s", api_key and "設定済み" or "未設定"))
    print(string.format("[Nudge Two Hats Debug] OpenRouter model: %s", model or "未設定"))
  end

  if not api_key then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] OPENROUTER_API_KEY が設定されていません")
    else
      vim.notify(api_key_error_msg, vim.log.levels.ERROR)
    end
    callback(api_key_error_msg)
    return
  end

  if not model then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] openrouter_model が設定されていません")
    else
      vim.notify(model_error_msg, vim.log.levels.ERROR)
    end
    callback(model_error_msg)
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
    log_file:write("OpenRouter API Key: " .. mask_secret(api_key) .. "\n")
    log_file:write("Endpoint: " .. get_openrouter_base_url() .. "/chat/completions\n")
    log_file:write("Model: " .. model .. "\n")
    if normalize_non_empty_string(config.openrouter_provider) then
      log_file:write("Provider: " .. config.openrouter_provider .. "\n")
    end
    if prompt then
      log_file:write("Using prompt: " .. prompt .. "\n")
    end
    log_file:close()
  end

  local context_settings = config[context_for] or config.notification or {}
  local system_prompt = prompt or state.current_prompt
  if not system_prompt then
    -- If no prompt is provided, use the system prompt as fallback (this should not happen with proper usage)
    system_prompt = context_settings.system_prompt or ""
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Warning: Using config system_prompt as fallback. This may indicate an issue with prompt generation.")
    end
  end
  local purpose_text = purpose or state.current_purpose or context_settings.purpose
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
      system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。通知用に%d文字以内で簡潔かつ完結したアドバイスをお願いします。文章は途中で切れないようにしてください。%s", context_settings.notify_message_length or 80, anti_duplication_prompt)
    else
      system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。仮想テキスト用に%d文字以内で簡潔かつ完結したアドバイスをお願いします。文章は途中で切れないようにしてください。%s", context_settings.virtual_text_message_length or context_settings.notify_message_length or 80, anti_duplication_prompt)
    end
  else
    if context_for == "notification" then
      system_prompt = system_prompt .. string.format("\nPlease respond in English. For notifications, provide concise and complete advice within %d characters. Ensure the message is meaningful and not cut off mid-sentence.%s", context_settings.notify_message_length or 80, anti_duplication_prompt)
    else
      system_prompt = system_prompt .. string.format("\nPlease respond in English. For virtual text, provide concise and complete advice within %d characters. Ensure the message is meaningful and not cut off mid-sentence.%s", context_settings.virtual_text_message_length or context_settings.notify_message_length or 80, anti_duplication_prompt)
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

  local request_obj = build_openrouter_request(model, system_prompt, sanitized_diff, 0.2)
  local ok, request_data = pcall(vim.fn.json_encode, request_obj)
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

  local function process_advice(advice)
    if not advice or advice == "" then
      callback(translate_message(config.translations.en.api_error))
      return
    end

    if previous_message and advice == previous_message then
      local suffix_variations = {
        ja = {" (改善案)", " (別のアプローチ)", " (追加提案)", " (代替案)", " (補足)"},
        en = {" (Alternative)", " (Improvement)", " (Additional)", " (Variant)", " (Supplement)"}
      }
      local variations = suffix_variations[output_lang] or suffix_variations.en
      local random_suffix = variations[math.random(#variations)]
      advice = advice .. random_suffix
    end

    if cache_key then
      advice_cache[cache_key] = advice
      table.insert(advice_cache_keys, cache_key)
      if #advice_cache_keys > MAX_ADVICE_CACHE_SIZE then
        local to_remove = table.remove(advice_cache_keys, 1)
        advice_cache[to_remove] = nil
      end
    end

    advice = apply_message_length_limit(advice, context_for)
    if config.translate_messages then
      advice = translate_message(advice)
    end
    callback(advice)
  end

  local has_plenary, curl = pcall(require, "plenary.curl")
  local full_url = get_openrouter_base_url() .. "/chat/completions"
  local headers = build_openrouter_headers(api_key)
  if has_plenary and config.use_plenary_curl == true then
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using plenary.curl\n")
      log_file:write("Full URL: " .. full_url .. "\n")
      log_file:close()
    end
    curl.post(full_url, {
      headers = headers,
      body = request_data,
      callback = function(response)
        vim.schedule(function()
          if response.status == 200 and response.body then
            local decode_ok, result
            if vim.json and vim.json.decode then
              decode_ok, result = pcall(vim.json.decode, response.body)
            else
              decode_ok, result = pcall(function() return vim.fn.json_decode(response.body) end)
            end
            local advice = decode_ok and extract_openrouter_message(result) or nil
            if advice then
              process_advice(advice)
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
    local temp_file = make_temp_json_path("request")
    local req_file = io.open(temp_file, "w")
    if not req_file then
      callback(translate_message(config.translations.en.api_error))
      return
    end
    req_file:write(request_data)
    req_file:close()
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using curl fallback\n")
      log_file:write("Full URL: " .. full_url .. "\n")
      log_file:close()
    end
    local curl_command = build_curl_command(full_url, temp_file, api_key)
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
            local advice = ok and extract_openrouter_message(response) or nil
            if advice then
              process_advice(advice)
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
  translate_with_openrouter = translate_with_openrouter,
  sanitize_text = sanitize_text,
  safe_truncate = safe_truncate,
  get_language = get_language,
  translate_message = translate_message,
  _make_temp_json_path = make_temp_json_path,
}

function M.update_config(new_config)
  config = new_config
end

-- Wrap get_openrouter_advice to handle different call patterns from init.lua
function M.get_openrouter_advice(diff, callback, arg1, arg2, arg3)
  -- 引数の型に基づいて振り分ける
  -- init.luaからの呼び出しパターン
  -- 1. api.get_openrouter_advice(diff, function(advice)
  -- 2. api.get_openrouter_advice(diff, function(advice), state
  -- 3. api.get_openrouter_advice(diff, function(advice), nil, nil, state
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
  return get_openrouter_advice(diff, callback, prompt, purpose, state)
end

return M
