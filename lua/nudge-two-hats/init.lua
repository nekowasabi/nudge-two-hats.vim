local M = {}

local state = {
  enabled = false,
  buf_content = {}, -- Store buffer content for diff calculation
  api_key = nil, -- Gemini API key
  last_api_call = 0, -- Timestamp of the last API call
}

local config = require("nudge-two-hats.config")


local function get_buf_diff(buf)
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local old = state.buf_content[buf]
  if old and old ~= content then
    local diff = vim.diff(old, content, { result_type = "unified" })
    if type(diff) == "string" then
      return content, diff
    end
  end
  return content, nil
end

local function get_prompt_for_buffer(buf)
  local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Buffer filetype: " .. filetype)
  end
  
  -- Check if we have a specific prompt for this filetype
  if filetype and config.filetype_prompts[filetype] then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using filetype-specific prompt for: " .. filetype)
    end
    return config.filetype_prompts[filetype]
  end
  
  return config.system_prompt
end

local function get_gemini_advice(diff, callback, prompt)
  local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
  
  if not api_key then
    vim.notify("Gemini API key not set. Set GEMINI_API_KEY environment variable or use :NudgeTwoHatsSetApiKey to set it.", vim.log.levels.ERROR)
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
  
  local request_data = vim.fn.json_encode({
    contents = {
      {
        parts = {
          {
            text = system_prompt .. "\n\n" .. diff
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
                  advice = string.sub(advice, 1, config.message_length)
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
              
              callback(advice)
            else
              callback("API error")
            end
          else
            vim.notify("Gemini API error: " .. (response.body or "Unknown error"), vim.log.levels.ERROR)
            callback("API error")
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
                  advice = string.sub(advice, 1, config.message_length)
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
              
              callback(advice)
            else
              callback("API error")
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
            
            vim.notify("Gemini API error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
          end)
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          vim.schedule(function()
            callback("API error")
          end)
        end
      end
    })
  end
end

local function create_autocmd(buf)
  local augroup = vim.api.nvim_create_augroup("nudge-two-hats-" .. buf, {})
  state.buf_content[buf] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

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
          vim.api.nvim_del_augroup_by_id(augroup)
          return
        end

        local content, diff = get_buf_diff(buf)
        
        if not diff then
          return
        end

        state.buf_content[buf] = content
        
        -- Check if minimum interval has passed since last API call
        local current_time = os.time()
        if (current_time - state.last_api_call) < config.min_interval then
          local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
          if log_file then
            log_file:write("Skipping API call - minimum interval not reached. Last call: " .. 
                          os.date("%c", state.last_api_call) .. ", Current time: " .. 
                          os.date("%c", current_time) .. ", Min interval: " .. 
                          config.min_interval .. " seconds\n")
            log_file:close()
          end
          return
        end
        
        state.last_api_call = current_time
        
        -- Get the appropriate prompt for this buffer's filetype
        local prompt = get_prompt_for_buffer(buf)
        
        get_gemini_advice(diff, function(advice)
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Advice: " .. advice)
          end
          
          vim.notify(advice, vim.log.levels.INFO, {
            title = "Nudge Two Hats",
            icon = "🎩",
          })
        end, prompt)
      end, config.execution_delay)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      state.buf_content[buf] = nil
      vim.api.nvim_del_augroup_by_id(augroup)
      return true
    end,
  })
end

function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end

  vim.api.nvim_create_user_command("NudgeTwoHatsToggle", function()
    state.enabled = not state.enabled
    vim.notify("Nudge Two Hats " .. (state.enabled and "enabled" or "disabled"), vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NudgeTwoHatsSetApiKey", function(args)
    state.api_key = args.args
    vim.notify("Gemini API key set", vim.log.levels.INFO)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("NudgeTwoHatsStart", function()
    local buf = vim.api.nvim_get_current_buf()
    create_autocmd(buf)
    state.enabled = true
    vim.notify("Nudge Two Hats started for current buffer", vim.log.levels.INFO)
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugToggle", function()
    config.debug_mode = not config.debug_mode
    vim.notify("Nudge Two Hats debug mode " .. (config.debug_mode and "enabled" or "disabled"), vim.log.levels.INFO)
    if config.debug_mode then
      print("[Nudge Two Hats] Debug mode enabled - nudge text will be printed to :messages")
    end
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsNow", function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    local current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    
    local original_content = state.buf_content[buf]
    
    if not original_content or original_content == current_content then
      if current_content and #current_content > 0 then
        state.buf_content[buf] = string.sub(current_content, 1, #current_content - 1)
      else
        state.buf_content[buf] = ""
      end
      
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Forcing diff calculation for NudgeTwoHatsNow")
        print("[Nudge Two Hats Debug] Original content length: " .. (original_content and #original_content or 0))
        print("[Nudge Two Hats Debug] Current content length: " .. #current_content)
      end
    end
    
    local content, diff = get_buf_diff(buf)
    
    if not diff then
      vim.notify("No changes detected to generate advice", vim.log.levels.INFO)
      
      state.buf_content[buf] = original_content
      return
    end
    
    state.buf_content[buf] = current_content
    
    state.last_api_call = 0
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Sending diff to Gemini API:")
      print(diff)
    end
    
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = get_prompt_for_buffer(buf)
    
    get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Advice: " .. advice)
      end
      
      vim.notify(advice, vim.log.levels.INFO, {
        title = "Nudge Two Hats",
        icon = "🎩",
      })
    end, prompt)
  end, {})
end

return M
