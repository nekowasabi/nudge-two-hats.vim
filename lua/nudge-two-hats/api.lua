local api = {}

local state
local config

function api.setup(shared_state, shared_config)
  state = shared_state
  config = shared_config
end

api.translations = {
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

function api.is_japanese(text)
  return text:match("[\227-\233]") ~= nil
end

function api.get_language()
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

function api.translate_message(message)
  if not config.translate_messages then
    return message
  end
  
  local target_lang = api.get_language()
  
  for key, value in pairs(api.translations[target_lang]) do
    if message == value then
      return message -- Already in target language
    end
  end
  
  for key, value in pairs(api.translations.en) do
    if message == value and api.translations[target_lang][key] then
      return api.translations[target_lang][key]
    end
  end
  
  for key, value in pairs(api.translations.ja) do
    if message == value and api.translations[target_lang][key] then
      return api.translations[target_lang][key]
    end
  end
  
  if config.translate_messages and target_lang ~= "en" and not api.is_japanese(message) then
    if target_lang == "ja" and message:len() < 100 then
      local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
      if api_key then
        local translated = api.translate_with_gemini(message, "en", "ja", api_key)
        if translated then
          return translated
        end
      end
    end
  elseif config.translate_messages and target_lang ~= "ja" and api.is_japanese(message) then
    if target_lang == "en" and message:len() < 100 then
      local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
      if api_key then
        local translated = api.translate_with_gemini(message, "ja", "en", api_key)
        if translated then
          return translated
        end
      end
    end
  end
  
  return message
end

function api.translate_with_gemini(text, source_lang, target_lang, api_key)
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Translating: " .. text)
  end
  
  local sanitized_text = text:gsub("[\0-\31\127]", ""):gsub('"', '\\"'):gsub("\\", "\\\\")
  
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

function api.get_buf_diff(buf)
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
  
  if #filetypes == 0 then
    table.insert(filetypes, "_default")
  end
  
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
  
  local first_notification = true
  for _, filetype in ipairs(filetypes) do
    if state.buf_content_by_filetype[buf][filetype] then
      first_notification = false
      break
    end
  end
  
  local force_diff = false
  local event_name = vim.v.event and vim.v.event.event
  if event_name == "BufWritePost" then
    force_diff = true
  end
  
  if first_notification and content and content ~= "" then
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
    end
    
    local context_lines = 10
    local start_line = math.max(1, cursor_line - context_lines)
    local end_line = math.min(line_count, cursor_line + context_lines)
    local context_line_count = end_line - start_line + 1
    
    local diff = string.format("--- a/dummy\n+++ b/current\n@@ -0,0 +1,%d @@\n", context_line_count)
    for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)) do
      diff = diff .. "+" .. line .. "\n"
    end
    
    local context_content = table.concat(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false), "\n")
    state.buf_content_by_filetype[buf][first_filetype] = context_content
    state.buf_content[buf] = context_content
    
    return context_content, diff, first_filetype
  end
  
  local old = nil
  local detected_filetype = nil
  
  if state.temp_files and state.temp_files[buf] then
    local temp_file_path = state.temp_files[buf]
    local temp_file = io.open(temp_file_path, "r")
    
    if temp_file then
      old = temp_file:read("*all")
      temp_file:close()
      
      if #filetypes > 0 then
        detected_filetype = filetypes[1]
      end
    end
  else
    for _, filetype in ipairs(filetypes) do
      if state.buf_content_by_filetype[buf] and state.buf_content_by_filetype[buf][filetype] then
        old = state.buf_content_by_filetype[buf][filetype]
        detected_filetype = filetype
        break
      end
    end
    
    if not old and state.buf_content[buf] then
      old = state.buf_content[buf]
      
      if not detected_filetype and #filetypes > 0 then
        detected_filetype = filetypes[1]
      end
    end
  end
  
  if old then
    if force_diff or old ~= content then
      local diff = vim.diff(old, content, { result_type = "unified" })
      
      if type(diff) == "string" and diff ~= "" then
        if detected_filetype then
          state.buf_content_by_filetype[buf][detected_filetype] = content
        end
        state.buf_content[buf] = content
        
        if state.temp_files and state.temp_files[buf] then
          local temp_file_path = state.temp_files[buf]
          
          os.execute("chmod 644 " .. temp_file_path)
          os.remove(temp_file_path)
          
          state.temp_files[buf] = nil
        end
        
        return content, diff, detected_filetype
      elseif force_diff then
        local minimal_diff = string.format("--- a/old\n+++ b/current\n@@ -1,1 +1,1 @@\n-%s\n+%s\n", 
          "No changes detected, but file was saved", "File saved at " .. os.date("%c"))
        
        if state.temp_files and state.temp_files[buf] then
          local temp_file_path = state.temp_files[buf]
          
          os.execute("chmod 644 " .. temp_file_path)
          os.remove(temp_file_path)
          
          state.temp_files[buf] = nil
        end
        
        return content, minimal_diff, detected_filetype
      end
    end
  end
  
  for _, filetype in ipairs(filetypes) do
    state.buf_content_by_filetype[buf][filetype] = content
  end
  state.buf_content[buf] = content
  
  return content, nil, nil
end

api.selected_hat = nil

function api.get_prompt_for_buffer(buf)
  local filetypes = {}
  
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  end
  
  if #filetypes == 0 then
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
    end
  end
  
  for _, filetype in ipairs(filetypes) do
    if filetype and config.filetype_prompts[filetype] then
      local filetype_prompt = config.filetype_prompts[filetype]
      
      if type(filetype_prompt) == "string" then
        api.selected_hat = nil
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
          api.selected_hat = hats[math.random(1, #hats)]
        end
        
        return string.format("I am a %s wearing the %s hat. %s. With %s emotions and a %s tone, I will advise: %s", 
                             role, api.selected_hat, direction, emotion, tone, prompt_text)
      end
    end
  end
  
  api.selected_hat = nil
  return config.system_prompt
end

function api.get_gemini_advice(diff, callback, prompt, purpose)
  local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
  
  if not api_key then
    local error_msg = api.translate_message(api.translations.en.api_key_not_set)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] APIキーが設定されていません")
    end
    vim.notify(error_msg, vim.log.levels.ERROR)
    return
  end

  local advice_cache = {}
  local advice_cache_keys = {}
  local MAX_ADVICE_CACHE_SIZE = 10
  
  local cache_key = nil
  if #diff < 10000 then  -- Only cache for reasonably sized diffs
    cache_key = diff .. (prompt or "") .. (purpose or "")
    
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
  
  local output_lang = api.get_language()
  if output_lang == "ja" then
    system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。%d文字程度の簡潔なアドバイスをお願いします。", config.message_length)
  else
    system_prompt = system_prompt .. string.format("\nPlease respond in English. Provide concise advice in about %d characters.", config.message_length)
  end
  
  local max_diff_size = 10000  -- 10KB is usually enough for context
  local truncated_diff = diff
  if #diff > max_diff_size then
    truncated_diff = string.sub(diff, 1, max_diff_size) .. "\n... (truncated for performance)"
  end
  
  local sanitized_diff = truncated_diff:gsub("[\0-\31\127]", ""):gsub('"', '\\"'):gsub("\\", "\\\\")
  
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
    local error_msg = api.translate_message(api.translations.en.api_error)
    vim.notify(error_msg .. ": JSON encoding failed", vim.log.levels.ERROR)
    callback(api.translate_message(api.translations.en.api_error))
    return
  end

  local has_plenary, curl = pcall(require, "plenary.curl")
  
  if has_plenary then
    local endpoint = config.api_endpoint:gsub("[<>]", "")
    local full_url = endpoint .. "?key=" .. api_key
    
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
              
              if config.translate_messages then
                advice = api.translate_message(advice)
              end
              
              callback(advice)
            else
              callback(api.translate_message(api.translations.en.api_error))
            end
          else
            local error_msg = api.translate_message(api.translations.en.api_error)
            vim.notify(error_msg .. ": " .. (response.body or api.translate_message(api.translations.en.unknown_error)), vim.log.levels.ERROR)
            callback(api.translate_message(api.translations.en.api_error))
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
              
              if config.translate_messages then
                advice = api.translate_message(advice)
              end
              
              callback(advice)
            else
              callback(api.translate_message(api.translations.en.api_error))
            end
          end)
        end
      end,
      on_exit = function(_, code)
        if vim.fn.filereadable(temp_file) == 1 then
          vim.fn.delete(temp_file)
        end
        
        if code ~= 0 then
          vim.schedule(function()
            callback(api.translate_message(api.translations.en.api_error))
          end)
        end
      end
    })
  end
end

return api
