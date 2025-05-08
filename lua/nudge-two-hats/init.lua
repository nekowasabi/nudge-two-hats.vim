local M = {}

local state = {
  enabled = false,
  buf_content = {}, -- Store buffer content for diff calculation
  api_key = nil, -- Gemini API key
}

local config = {
  system_prompt = "Give a 10-character advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  execution_delay = 3000, -- Delay in milliseconds
  gemini_model = "gemini-2.0-flash", -- Using Gemini 2.0 Flash as recommended
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
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

  local curl_command = string.format(
    "curl -s -X POST %s?key=%s -H 'Content-Type: application/json' -d '{\"contents\":[{\"parts\":[{\"text\":\"%s\\n\\n%s\"}]}]}'",
    config.api_endpoint,
    api_key,
    config.system_prompt,
    vim.fn.escape(diff, '"\\\n')
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
