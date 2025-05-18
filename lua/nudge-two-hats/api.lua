local config = require("nudge-two-hats.config")

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

-- Export the functions
return {
  is_japanese = is_japanese,
  translate_with_gemini = translate_with_gemini,
  sanitize_text = sanitize_text,
  safe_truncate = safe_truncate
}