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
local api = require("nudge-two-hats.api")
local autocmd = require("nudge-two-hats.autocmd")

api.setup(state, config)
autocmd.setup(state, config, api)



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
    local status = state.enabled and api.translate_message(api.translations.en.enabled) or api.translate_message(api.translations.en.disabled)
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
      
      autocmd.create_autocmd(buf)
      
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
          autocmd.clear_virtual_text(buf)
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
    vim.notify(api.translate_message(api.translations.en.api_key_set), vim.log.levels.INFO)
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
            
            autocmd.create_autocmd(file_buf)
            autocmd.setup_virtual_text(file_buf)
            
            -- print("[Nudge Two Hats] Added file: " .. file_path .. " with filetype: " .. file_filetype)
          else
            -- print("[Nudge Two Hats] Warning: Could not determine filetype for file: " .. file_path)
          end
        else
          -- Check if it's a filetype specification
          if config.filetype_prompts[args.args] or args.args == "all" then
            table.insert(filetypes, args.args)
            -- print("[Nudge Two Hats] Using specified filetype: " .. args.args)
          else
            -- print("[Nudge Two Hats] Warning: File not found: " .. file_path)
          end
        end
      end
    else
      -- If no arguments, use current buffer's filetype
      if current_filetype and current_filetype ~= "" then
        table.insert(filetypes, current_filetype)
        using_current_filetype = true
        -- print("[Nudge Two Hats] Using current buffer's filetype: " .. current_filetype)
      end
    end
    
    if #filetypes == 0 and current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
      using_current_filetype = true
      -- print("[Nudge Two Hats] Fallback to current buffer's filetype: " .. current_filetype)
    end
    
    -- Store the filetypes in state
    if #filetypes > 0 then
      state.buf_filetypes[buf] = table.concat(filetypes, ",")
      
      state.virtual_text.last_cursor_move = state.virtual_text.last_cursor_move or {}
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      autocmd.create_autocmd(buf)
      autocmd.setup_virtual_text(buf)
    end
    
    state.enabled = true
    
    autocmd.create_autocmd(buf)
    autocmd.setup_virtual_text(buf)
    
    -- vim.notify(api.translate_message(api.translations.en.started_buffer), vim.log.levels.INFO)
    
    if not state.original_updatetime then
      state.original_updatetime = vim.o.updatetime
    end
    vim.o.updatetime = 1000
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Set updatetime to 1000ms (original: " .. state.original_updatetime .. "ms)")
      vim.notify(api.translate_message(api.translations.en.debug_enabled), vim.log.levels.INFO)
    end
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugVirtualText", function()
    local buf = vim.api.nvim_get_current_buf()
    local augroup_id = vim.api.nvim_create_augroup("nudge-two-hats-debug-" .. buf, {})
    
    state.debug_augroup_ids = state.debug_augroup_ids or {}
    state.debug_augroup_ids[buf] = augroup_id
    
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      log_file:write("=== Debug mode enabled at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
      log_file:write("updatetime: " .. vim.o.updatetime .. "ms\n")
      log_file:write("idle_time setting: " .. config.virtual_text.idle_time .. " minutes (" .. (config.virtual_text.idle_time * 60) .. " seconds)\n")
      log_file:write("cursor_idle_delay setting: " .. (config.virtual_text.cursor_idle_delay or 5) .. " minutes\n")
      
      local current_time = os.time()
      local last_cursor_move_time = state.virtual_text.last_cursor_move[buf] or 0
      local idle_time = current_time - last_cursor_move_time
      
      log_file:write("Current time: " .. os.date("%Y-%m-%d %H:%M:%S", current_time) .. "\n")
      log_file:write("Last cursor move time: " .. os.date("%Y-%m-%d %H:%M:%S", last_cursor_move_time) .. "\n")
      log_file:write("Idle time: " .. idle_time .. " seconds\n")
      
      if state.timers.virtual_text[buf] then
        local timer_info = vim.fn.timer_info(state.timers.virtual_text[buf])
        if timer_info and #timer_info > 0 then
          log_file:write("Virtual text timer info: " .. vim.inspect(timer_info) .. "\n")
        else
          log_file:write("Virtual text timer ID exists but timer not found\n")
        end
      else
        log_file:write("No virtual text timer for this buffer\n")
      end
      
      log_file:close()
    end
    
    local current_pos = vim.api.nvim_win_get_cursor(0)
    state.debug_cursor_pos = { row = current_pos[1], col = current_pos[2] }
    
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup_id,
      buffer = buf,
      callback = function()
        local new_pos = vim.api.nvim_win_get_cursor(0)
        local row_diff = new_pos[1] - state.debug_cursor_pos.row
        local col_diff = new_pos[2] - state.debug_cursor_pos.col
        
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== Debug CursorMoved at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:write(string.format("Cursor moved from (%d,%d) to (%d,%d) - diff: (%d,%d)\n", 
            state.debug_cursor_pos.row, state.debug_cursor_pos.col, 
            new_pos[1], new_pos[2], 
            row_diff, col_diff))
          log_file:close()
        end
        
        state.debug_cursor_pos = { row = new_pos[1], col = new_pos[2] }
      end
    })
    
    vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
      group = augroup_id,
      buffer = buf,
      callback = function()
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== Debug buffer deleted at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:close()
        end
        
        state.debug_augroup_ids[buf] = nil
      end
    })
    
    vim.notify("Debug mode enabled for buffer " .. buf .. ". Check /tmp/nudge_two_hats_virtual_text_debug.log for details.", vim.log.levels.INFO)
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsNow", function()
    local buf = vim.api.nvim_get_current_buf()
    
    if not state.enabled then
      vim.notify("Nudge Two Hats is not enabled. Use :NudgeTwoHatsToggle to enable it first.", vim.log.levels.ERROR)
      return
    end
    
    autocmd.start_notification_timer(buf, "NudgeTwoHatsNow")
    
    vim.notify("Nudge Two Hats notification requested for current buffer.", vim.log.levels.INFO)
  end, {})
  
  -- Set up global event handlers
  autocmd.setup_global_events()
end

return M
      if log_file then
        log_file:write(string.format("Insert mode exited in buffer %d at %s, cleared virtual text\n", 
          buf, os.date("%Y-%m-%d %H:%M:%S")))
        log_file:close()
      end
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
      if config.debug_mode then
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== CursorHold triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:write("Buffer: " .. buf .. "\n")
          log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
          log_file:write("updatetime: " .. vim.o.updatetime .. "ms\n")
          log_file:write("idle_time setting: " .. config.virtual_text.idle_time .. " minutes (" .. (config.virtual_text.idle_time * 60) .. " seconds)\n")
        
          if not state.enabled then
            log_file:write("Plugin not enabled, exiting CursorHold handler\n\n")
            log_file:close()
          end
        end
      end
      
      if not state.enabled then
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
      if idle_condition_met and not state.timers.virtual_text[buf] then
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


function M.stop_virtual_text_timer(buf)
  state.timers = state.timers or {}
  state.timers.virtual_text = state.timers.virtual_text or {}
  
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
  if config.debug_mode then
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      log_file:write("=== display_virtual_text called at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
      log_file:write("Advice length: " .. #advice .. " characters\n")
      log_file:write("Advice: " .. advice .. "\n")
    
      if not state.enabled then
        log_file:write("Plugin not enabled, exiting display_virtual_text\n\n")
        log_file:close()
      end
    end
  end
  
  if not state.enabled then
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
    
    state.timers = state.timers or {}
    state.timers.virtual_text = state.timers.virtual_text or {}
    state.timers.notification = state.timers.notification or {}
    
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
    
    -- Get cursor context (±20 lines) instead of entire buffer
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local cursor_row = cursor_pos[1] -- 1-based
    local line_count = vim.api.nvim_buf_line_count(buf)
    
    -- Calculate context range (20 lines above and below cursor)
    local context_start = math.max(1, cursor_row - 20)
    local context_end = math.min(line_count, cursor_row + 20)
    
    local context_lines = vim.api.nvim_buf_get_lines(buf, context_start - 1, context_end, false)
    local context_content = table.concat(context_lines, "\n")
    
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
      -- Create a diff with just the context
      diff = string.format("@@ -%d,%d +%d,%d @@\n+ %s", 
                          context_start, #context_lines, context_start, #context_lines, 
                          context_content)
      diff_filetype = filetypes[1]
      
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Created forced diff for NudgeTwoHatsNow command")
        print("[Nudge Two Hats Debug] コンテキスト範囲: " .. context_start .. "-" .. context_end .. " 行")
      end
    end
    
    -- Restore original stored content after diff generation
    state.buf_content[buf] = stored_content
    state.buf_content_by_filetype[buf] = stored_content_by_filetype
    
    for _, filetype in ipairs(filetypes) do
      if not state.buf_content_by_filetype[buf] then
        state.buf_content_by_filetype[buf] = {}
      end
      state.buf_content_by_filetype[buf][filetype] = context_content
    end
    
    state.buf_content[buf] = context_content
    
    state.last_api_call = 0
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Sending diff to Gemini API for filetype: " .. (diff_filetype or "unknown"))
      print(diff)
    end
    
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = get_prompt_for_buffer(buf)
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します")
    end
    
    get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] APIコールバック実行: " .. (advice or "アドバイスなし"))
      end
      
      local title = "Nudge Two Hats"
      if selected_hat then
        title = selected_hat
      end
      
      if config.debug_mode then
        print("[Nudge Two Hats Debug] vim.notifyを呼び出します: " .. title)
      end
      
      vim.notify(advice, vim.log.levels.INFO, {
        title = title,
        icon = "🎩",
      })
      
      if config.debug_mode then
        print("\n=== Nudge Two Hats 通知 ===")
        print(advice)
        print("==========================")
      end
      
      state.virtual_text.last_advice[buf] = advice
      
      if content then
        -- Update content for all filetypes
        state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
        
        -- Get the filetypes for this buffer within the callback
        local callback_filetypes = {}
        if state.buf_filetypes[buf] then
          for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
            table.insert(callback_filetypes, filetype)
          end
        else
          local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
          if current_filetype and current_filetype ~= "" then
            table.insert(callback_filetypes, current_filetype)
          end
        end
        
        if #callback_filetypes > 0 then
          for _, filetype in ipairs(callback_filetypes) do
            state.buf_content_by_filetype[buf][filetype] = content
          end
        else
          state.buf_content_by_filetype[buf]["_default"] = content
        end
        
        state.buf_content[buf] = content
        
        if config.debug_mode then
          print("[Nudge Two Hats Debug] バッファ内容を更新しました: " .. table.concat(callback_filetypes, ", "))
        end
      end
      
    end, prompt, config.purpose)
  end, {})
  
  vim.api.nvim_create_user_command("NudgeTwoHatsDebugNotify", function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    state.timers = state.timers or {}
    state.timers.virtual_text = state.timers.virtual_text or {}
    state.timers.notification = state.timers.notification or {}
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 通知処理を強制的に発火させます")
    end
    
    -- Get current buffer filetypes
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
      end
    end
    
    if #filetypes == 0 then
      vim.notify("No filetypes specified or detected", vim.log.levels.INFO)
      return
    end
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Buffer filetypes: " .. table.concat(filetypes, ", "))
    end
    
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local cursor_row = cursor_pos[1] -- 1-based
    local line_count = vim.api.nvim_buf_line_count(buf)
    
    -- Calculate context range (20 lines above and below cursor)
    local context_start = math.max(1, cursor_row - 20)
    local context_end = math.min(line_count, cursor_row + 20)
    
    local context_lines = vim.api.nvim_buf_get_lines(buf, context_start - 1, context_end, false)
    local context_content = table.concat(context_lines, "\n")
    
    -- Create a diff with just the context
    local diff = string.format("@@ -%d,%d +%d,%d @@\n+ %s", 
                              context_start, #context_lines, context_start, #context_lines, 
                              context_content)
    
    local current_filetype = filetypes[1]
    
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = get_prompt_for_buffer(buf)
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 強制的に通知処理を実行します")
      print("[Nudge Two Hats Debug] Filetype: " .. (current_filetype or "unknown"))
      print("[Nudge Two Hats Debug] コンテキスト範囲: " .. context_start .. "-" .. context_end .. " 行")
    end
    
    state.last_api_call = 0
    
    get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] 通知処理の結果: " .. advice)
      end
      
      local title = "Nudge Two Hats (Debug)"
      if selected_hat then
        title = selected_hat .. " (Debug)"
      end
      
      vim.notify(advice, vim.log.levels.INFO, {
        title = title,
        icon = "🐛",
      })
      
      state.virtual_text.last_advice[buf] = advice
    end, prompt, config.purpose)
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 通知処理の発火が完了しました")
    end
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
        
        if config.debug_mode then
          local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
          if log_file then
            log_file:write("=== BufEnter triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
            log_file:write("Current buffer: " .. buf .. "\n")
            log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
            log_file:close()
          end
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
        if config.debug_mode then
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
      end
      
      -- Restore original updatetime
      if state.original_updatetime then
        vim.o.updatetime = state.original_updatetime
      end
    end
  })
  
  vim.api.nvim_create_autocmd("VimLeavePre", {
    pattern = "*",
    callback = function()
      if config.debug_mode then
        print("[Nudge Two Hats Debug] エディタ終了時にすべてのバッファファイルをクリーンアップします")
      end
      
      -- Delete all nudge_two_hats_buffer_*.txt files
      local result = vim.fn.system("find /tmp -name 'nudge_two_hats_buffer_*.txt' -type f -delete")
      
      if config.debug_mode then
        print("[Nudge Two Hats Debug] バッファファイルのクリーンアップが完了しました")
      end
    end
  })
end

return M
