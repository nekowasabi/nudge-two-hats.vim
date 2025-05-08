local M = {}

local state = {
  enabled = false,
  buf_content = {}, -- Store buffer content for diff calculation
  api_key = nil, -- Gemini API key
}

local config = {
  system_prompt = "Give a 10-character advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  execution_delay = 3000, -- Delay in milliseconds
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Updated to latest Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
}

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

local function get_gemini_advice(diff, callback)
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
    log_file:close()
  end

  local request_data = vim.fn.json_encode({
    contents = {
      {
        parts = {
          {
            text = config.system_prompt .. "\n\n" .. diff
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
    local endpoint = config.api_endpoint:gsub("[<>]", "") .. "?key=" .. api_key
    
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using plenary.curl\n")
      log_file:write("Clean endpoint: " .. endpoint .. "\n")
      log_file:close()
    end
    
    curl.post(endpoint, {
      headers = {
        ["Content-Type"] = "application/json",
      },
      body = request_data,
      callback = function(response)
        if response.status == 200 and response.body then
          local result = vim.fn.json_decode(response.body)
          if result and result.candidates and result.candidates[1] and 
             result.candidates[1].content and result.candidates[1].content.parts and 
             result.candidates[1].content.parts[1] and result.candidates[1].content.parts[1].text then
            local advice = result.candidates[1].content.parts[1].text
            if #advice > 10 then
              advice = string.sub(advice, 1, 10)
            end
            callback(advice)
          else
            callback("API error")
          end
        else
          vim.notify("Gemini API error: " .. (response.body or "Unknown error"), vim.log.levels.ERROR)
          callback("API error")
        end
      end
    })
  else
    local endpoint = config.api_endpoint:gsub("[<>]", "")
    local temp_file = "/tmp/nudge_two_hats_request.json"
    
    local req_file = io.open(temp_file, "w")
    if req_file then
      req_file:write(request_data)
      req_file:close()
    end
    
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using curl fallback\n")
      log_file:write("Command: curl -s -X POST " .. endpoint .. "?key=" .. string.sub(api_key, 1, 5) .. "... -H 'Content-Type: application/json' -d @" .. temp_file .. "\n")
      log_file:close()
    end
    
    local curl_command = string.format(
      "curl -s -X POST %s?key=%s -H 'Content-Type: application/json' -d @%s",
      endpoint,
      api_key,
      temp_file
    )
    
    vim.fn.jobstart(curl_command, {
      on_stdout = function(_, data)
        if data and #data > 0 and data[1] ~= "" then
          local response = vim.fn.json_decode(table.concat(data, "\n"))
          if response and response.candidates and response.candidates[1] and 
             response.candidates[1].content and response.candidates[1].content.parts and 
             response.candidates[1].content.parts[1] and response.candidates[1].content.parts[1].text then
            local advice = response.candidates[1].content.parts[1].text
            if #advice > 10 then
              advice = string.sub(advice, 1, 10)
            end
            callback(advice)
          else
            callback("API error")
          end
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 0 and data[1] ~= "" then
          local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
          if log_file then
            log_file:write("Curl stderr: " .. table.concat(data, "\n") .. "\n")
            log_file:close()
          end
          
          vim.notify("Gemini API error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          callback("API error")
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
        
        get_gemini_advice(diff, function(advice)
          vim.notify(advice, vim.log.levels.INFO, {
            title = "Nudge Two Hats",
            icon = "🎩",
          })
        end)
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
end

return M
