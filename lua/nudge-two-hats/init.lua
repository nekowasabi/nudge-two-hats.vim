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
