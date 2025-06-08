local M = {}

local state = {
  enabled = false,
  buf_content = {}, -- Store buffer content for diff calculation (legacy, kept for backward compatibility)
  buf_content_by_filetype = {}, -- Store buffer content by buffer ID and filetype
  buf_filetypes = {}, -- Store buffer filetypes when NudgeTwoHatsStart is executed
  api_key = nil, -- Gemini API key
  last_api_call_notification = 0, -- Timestamp of the last API call for notifications
  last_api_call_virtual_text = 0, -- Timestamp of the last API call for virtual text
  last_cursor_pos = {}, -- Stores last known cursor position {buf -> {win, lnum, col, coladd}}
  timers = {
    notification = {}, -- Store notification timer IDs by buffer (for API requests)
    virtual_text = {}  -- Store virtual text timer IDs by buffer (for display)
  },
  virtual_text = {
    namespace = nil, -- Namespace for virtual text extmarks
    extmarks = {}, -- Store extmark IDs by buffer
    last_advice = {}, -- For virtual text
    is_displayed = {} -- Tracks if virtual text is currently displayed for a buffer
  },
  notifications = { -- New structure for notifications
    last_advice = {} -- To store last notification message per buffer
  }
}

math.randomseed(os.time())

local config = require("nudge-two-hats.config")

-- Import the API module for all functions
local api = require("nudge-two-hats.api")

-- Import the buffer module
local buffer = require("nudge-two-hats.buffer")

-- Import the autocmd module
local autocmd = require("nudge-two-hats.autocmd")

-- Import the timer module
local timer = require("nudge-two-hats.timer")

-- -- Use imported safe_truncate function
-- local safe_truncate = api.safe_truncate

-- local advice_cache = {}
-- local advice_cache_keys = {}
-- local MAX_ADVICE_CACHE_SIZE = 10
-- timer.luaからの関数を呼び出すラッパー関数
function M.stop_notification_timer(buf)
  return timer.stop_notification_timer(buf, state)
end

-- timer.luaからの関数を呼び出すラッパー関数
function M.stop_virtual_text_timer(buf)
  return timer.stop_virtual_text_timer(buf, state)
end

-- timer.luaからの関数を呼び出すラッパー関数
function M.start_notification_timer(buf, event_name)
  return timer.start_notification_timer(buf, event_name, state, M.stop_notification_timer)
end

-- timer.luaからの関数を呼び出すラッパー関数
function M.stop_timer(buf)
  -- This function is now only expected to stop the virtual text timer.
  -- The notification timer will be managed independently.
  return timer.stop_virtual_text_timer(buf, state)
end

-- timer.luaからの関数を呼び出すラッパー関数
function M.start_virtual_text_timer(buf, event_name)
  -- The callback to M.start_virtual_text_timer itself (previously in state.start_virtual_text_timer_callback)
  -- is handled by the recurring nature of the timer in timer.lua now.
  return timer.start_virtual_text_timer(buf, event_name, state, M.display_virtual_text)
end

-- timer.luaからの関数を呼び出すラッパー関数（カーソル停止検知）
function M.pause_notification_timer(buf)
  return timer.pause_notification_timer(buf, state)
end

-- timer.luaからの関数を呼び出すラッパー関数（カーソル停止からの復活）
function M.resume_notification_timer(buf)
  return timer.resume_notification_timer(buf, state, M.stop_notification_timer)
end

-- virtual_textモジュールをインポート
local virtual_text = require("nudge-two-hats.virtual_text")

-- clear_virtual_textのラッパー関数
function M.clear_virtual_text(buf)
  return virtual_text.clear_virtual_text(buf)
end

-- display_virtual_textのラッパー関数
function M.display_virtual_text(buf, advice)
  -- When new virtual text is displayed, we should stop any existing virtual text timer 
  -- for that buffer, as new advice has been received and displayed.
  -- The timer.start_virtual_text_timer will be called again if needed by other events (e.g. BufEnter, NudgeTwoHatsToggle)
  -- or by its own recurring callback if no new diff is found.
  M.stop_virtual_text_timer(buf) 
  return virtual_text.display_virtual_text(buf, advice)
end

function M.setup(opts)
  if opts then
    -- Mark as user-configured to prevent default setup
    vim.g.nudge_two_hats_configured = true
    -- Complete config replacement to ensure user settings override defaults
    local user_config = vim.tbl_deep_extend("force", config, opts)
    config = user_config
    api.update_config(config)
    -- Update buffer module config
    local buffer = require("nudge-two-hats.buffer")
    buffer.update_config(config)
    -- Update timer module config
    timer.update_config(config)
    -- Update virtual_text module config
    virtual_text.update_config(config)
  end
  -- virtual_textモジュールに状態を渡す
  virtual_text.init(state)
  -- stop_timer関数の参照をstateに追加
  state.stop_timer = M.stop_timer
  vim.api.nvim_set_hl(0, "NudgeTwoHatsVirtualText", {
    fg = config.virtual_text.text_color,
    bg = config.virtual_text.background_color,
  })
  state.virtual_text.namespace = vim.api.nvim_create_namespace("nudge-two-hats-virtual-text")
  vim.api.nvim_create_user_command("NudgeTwoHatsToggle", function(args)
    state.enabled = not state.enabled
    local status = state.enabled and api.translate_message(config.translations.en.enabled) or api.translate_message(config.translations.en.disabled)
    local toggle_message = "Nudge Two Hats " .. status
    if config.debug_mode then
      print("[Nudge Two Hats Debug] " .. toggle_message)
    else
      vim.notify(toggle_message, vim.log.levels.INFO)
    end
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
      -- create_autocmd関数をautocmdモジュールから呼び出します
      -- The autocmd module now uses its internally stored m_state and m_plugin_functions
      autocmd.create_autocmd(buf)
      -- Start both timers when enabling
      M.start_notification_timer(buf, "NudgeTwoHatsToggle_enable")
      M.start_virtual_text_timer(buf, "NudgeTwoHatsToggle_enable")
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Set updatetime to 1000ms (original: " .. state.original_updatetime .. "ms)")
        print("[Nudge Two Hats Debug] Notification and Virtual Text timers started for buffer " .. buf .. " via NudgeTwoHatsToggle.")
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
      -- Stop both timers for all relevant buffers
      for b, _ in pairs(state.buf_filetypes) do -- Iterate over buffers managed by the plugin
        if vim.api.nvim_buf_is_valid(b) then
          M.stop_notification_timer(b)
          M.stop_virtual_text_timer(b)
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Notification and Virtual Text timers stopped for buffer " .. b .. " via NudgeTwoHatsToggle disable.")
          end
        end
      end
      -- Clear any legacy timers just in case (though they should not be active with new code)
      if state.virtual_text.timers then
         for b, timer_id in pairs(state.virtual_text.timers) do
           if timer_id then
             vim.fn.timer_stop(timer_id)
             state.virtual_text.timers[b] = nil
           end
         end
      end
    end
  end, {})


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
          end
        end
      end
    end
    if #filetypes == 0 and current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
      using_current_filetype = true
    end
    if #filetypes == 0 then
      vim.notify("No filetypes specified or detected", vim.log.levels.INFO)
      return
    end
    -- Store the filetypes in state
    state.buf_filetypes[buf] = table.concat(filetypes, ",")
    state.enabled = true
    local augroup_name = "nudge-two-hats-" .. buf
    pcall(vim.api.nvim_del_augroup_by_name, augroup_name)
    -- create_autocmd関数をautocmdモジュールから呼び出します
    -- The autocmd module now uses its internally stored m_state and m_plugin_functions
    autocmd.create_autocmd(buf)
    -- Start both timers when enabling via NudgeTwoHatsStart
    M.start_notification_timer(buf, "NudgeTwoHatsStart")
    M.start_virtual_text_timer(buf, "NudgeTwoHatsStart")
    local filetype_str = table.concat(filetypes, ", ")
    local source_str = using_current_filetype and "current buffer" or "specified files"
    local enable_message = string.format("Nudge Two Hats enabled for filetypes: %s (from %s)", filetype_str, source_str)
    if config.debug_mode then
      -- print("[Nudge Two Hats Debug] " .. enable_message)
      -- print("[Nudge Two Hats Debug] Notification and Virtual Text timers started for buffer " .. buf .. " via NudgeTwoHatsStart.")
    else
      -- vim.notify(enable_message, vim.log.levels.INFO)
    end
  end, { nargs = "*" })
  vim.api.nvim_create_user_command("NudgeTwoHatsDebug", function()
    print("==========================================")
    print("Nudge Two Hats Debug Information")
    print("==========================================")
    print(string.format("Plugin enabled: %s", state.enabled and "true" or "false"))
    print(string.format("Debug mode: %s", config.debug_mode and "true" or "false"))
    print(string.format("API key set: %s", state.api_key and "true" or "false"))
    print(string.format("Original updatetime: %s", state.original_updatetime or "not set"))
    print(string.format("Current updatetime: %s", vim.o.updatetime))
    print(string.format("Virtual text idle time: %s minutes", config.virtual_text_interval_seconds / 60))
    print(string.format("Notification idle time: %s minutes", config.notify_interval_seconds / 60))
    print(string.format("Last API call notification: %s", state.last_api_call_notification or "never"))
    print(string.format("Last API call virtual text: %s", state.last_api_call_virtual_text or "never"))
    print("\nActive Buffers:")

    local active_notification_timers = 0
    local active_virtual_text_timers = 0
    local inactive_buffers = 0

    state.timers = state.timers or {}
    state.timers.virtual_text = state.timers.virtual_text or {}
    state.timers.notification = state.timers.notification or {}
    for buf, filetypes in pairs(state.buf_filetypes) do
      if vim.api.nvim_buf_is_valid(buf) then
        local notification_timer_id = state.timers.notification[buf]
        local virtual_text_timer_id = state.timers.virtual_text[buf]
        local legacy_timer_id = state.virtual_text.timers and state.virtual_text.timers[buf]
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
  -- Helper function to prepare buffer and get context
  local function prepare_buffer_context(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
      return nil
    end
    
    state.timers = state.timers or {}
    state.timers.virtual_text = state.timers.virtual_text or {}
    state.timers.notification = state.timers.notification or {}
    
    local filetypes = {}
    if state.buf_filetypes[buf] then
      for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
        table.insert(filetypes, filetype)
      end
    else
      local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
      if current_filetype and current_filetype ~= "" then
        table.insert(filetypes, current_filetype)
        state.buf_filetypes[buf] = current_filetype
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] 初期化：現在のfiletype (%s) を保存しました", current_filetype or "nil"))
        end
      end
    end
    
    if #filetypes == 0 then
      vim.notify("No filetypes specified or detected", vim.log.levels.INFO)
      return nil
    end
    
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local cursor_row = cursor_pos[1]
    local line_count = vim.api.nvim_buf_line_count(buf)
    local context_start = math.max(1, cursor_row - 20)
    local context_end = math.min(line_count, cursor_row + 20)
    local context_lines = vim.api.nvim_buf_get_lines(buf, context_start - 1, context_end, false)
    local context_content = table.concat(context_lines, "\n")
    
    return {
      filetypes = filetypes,
      context_content = context_content,
      context_start = context_start,
      context_end = context_end,
      context_lines = context_lines
    }
  end
  
  -- Helper function to execute notification API call
  local function execute_notification_api(buf, diff, diff_filetype, content, filetypes)
    local prompt = buffer.get_prompt_for_buffer(buf, state, "notification")
    state.context_for = "notification"
    
    api.get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] 通知用APIコールバック実行: " .. (advice or "アドバイスなし"))
      end
      
      if advice then
        state.notifications = state.notifications or {}
        state.notifications.last_advice = state.notifications.last_advice or {}
        state.notifications.last_advice[buf] = advice
      end
      
      local title = "Nudge Two Hats"
      local current_selected_hat = buffer.get_selected_hat()
      if current_selected_hat then
        title = current_selected_hat
      end
      
      vim.notify(advice, vim.log.levels.INFO, { title = title, icon = "🎩" })
      
      if config.debug_mode then
        print("\n=== Nudge Two Hats 通知 (NudgeTwoHatsNow) ===")
        print(advice)
        print("============================================")
      end
      
      if content then
        state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
        for _, ft in ipairs(filetypes) do
          state.buf_content_by_filetype[buf][ft] = content
        end
        state.buf_content[buf] = content
      end
    end, prompt, config.purpose, state)
  end
  
  -- Helper function to execute virtual text API call
  local function execute_virtual_text_api(buf, diff, diff_filetype)
    state.context_for = "virtual_text"
    local vt_prompt = buffer.get_prompt_for_buffer(buf, state, "virtual_text")
    
    api.get_gemini_advice(diff, function(virtual_text_advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] 仮想テキスト用APIコールバック実行: " .. (virtual_text_advice or "アドバイスなし"))
      end
      
      if virtual_text_advice then
        state.virtual_text = state.virtual_text or {}
        state.virtual_text.last_advice = state.virtual_text.last_advice or {}
        state.virtual_text.last_advice[buf] = virtual_text_advice
        
        M.display_virtual_text(buf, virtual_text_advice)
        
        if config.debug_mode then
          print("\n=== Nudge Two Hats 仮想テキスト (NudgeTwoHatsNow) ===")
          print(virtual_text_advice)
          print("===================================================")
        end
      end
    end, vt_prompt, config.purpose, state)
  end

  vim.api.nvim_create_user_command("NudgeTwoHatsNow", function()
    local buf = vim.api.nvim_get_current_buf()
    local context_data = prepare_buffer_context(buf)
    if not context_data then
      return
    end
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Using filetypes: " .. table.concat(context_data.filetypes, ", "))
    end
    
    local stored_content = state.buf_content[buf]
    local stored_content_by_filetype = state.buf_content_by_filetype[buf] or {}
    
    local content, diff, diff_filetype = buffer.get_buf_diff(buf, state)
    if not diff then
      diff = string.format("@@ -%d,%d +%d,%d @@\n+ %s",
                          context_data.context_start, #context_data.context_lines,
                          context_data.context_start, #context_data.context_lines,
                          context_data.context_content)
      diff_filetype = context_data.filetypes[1]
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Created forced diff for NudgeTwoHatsNow command")
      end
    end
    
    for _, filetype in ipairs(context_data.filetypes) do
      if not state.buf_content_by_filetype[buf] then
        state.buf_content_by_filetype[buf] = {}
      end
      state.buf_content_by_filetype[buf][filetype] = context_data.context_content
    end
    state.buf_content[buf] = context_data.context_content
    
    state.last_api_call_notification = 0
    state.last_api_call_virtual_text = 0
    
    execute_notification_api(buf, diff, diff_filetype, content, context_data.filetypes)
    execute_virtual_text_api(buf, diff, diff_filetype)
  end, { nargs = "*" })
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
    local prompt = buffer.get_prompt_for_buffer(buf, state, "notification")
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 強制的に通知処理を実行します")
      print("[Nudge Two Hats Debug] Filetype: " .. (current_filetype or "unknown"))
      print("[Nudge Two Hats Debug] コンテキスト範囲: " .. context_start .. "-" .. context_end .. " 行")
    end
    state.last_api_call_notification = 0
    state.last_api_call_virtual_text = 0
    -- 通知用にGemini APIを呼び出し
    state.context_for = "notification"
    api.get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] 通知処理の結果: " .. advice)
      end
      local title = "Nudge Two Hats (Debug)"
      local selected_hat = buffer.get_selected_hat()
      if selected_hat then
        title = selected_hat .. " (Debug)"
      end
      vim.notify(advice, vim.log.levels.INFO, {
        title = title,
        icon = "🐛",
      })
      
      -- 仮想テキスト用に別途Gemini APIを呼び出し
      state.context_for = "virtual_text"
      local vt_prompt = buffer.get_prompt_for_buffer(buf, state, "virtual_text")
      api.get_gemini_advice(diff, function(virtual_text_advice)
        if config.debug_mode then
          print("[Nudge Two Hats Debug] デバッグモードの仮想テキスト処理の結果: " .. virtual_text_advice)
        end
        state.virtual_text.last_advice[buf] = virtual_text_advice
      end, vt_prompt, config.purpose, state) -- Corrected arguments for the inner get_gemini_advice
    end, prompt, config.purpose, state) -- Corrected arguments for the outer get_gemini_advice
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 通知処理の発火が完了しました")
    end
  end, {})
  -- BufEnter autocmdはautocmd.luaに移動しました
  local autocmd = require("nudge-two-hats.autocmd")
  local plugin_functions = {
    stop_notification_timer = M.stop_notification_timer,
    stop_virtual_text_timer = M.stop_virtual_text_timer,
    start_virtual_text_timer = M.start_virtual_text_timer,
    -- For autocmd.create_autocmd to access other functions if needed via m_plugin_functions
    start_notification_timer = M.start_notification_timer,
    clear_virtual_text = M.clear_virtual_text,
    pause_notification_timer = M.pause_notification_timer,
    resume_notification_timer = M.resume_notification_timer
  }
  autocmd.update_config(config)
  -- Pass all necessary components to autocmd.setup
  autocmd.setup(config, state, plugin_functions)
end

return M
