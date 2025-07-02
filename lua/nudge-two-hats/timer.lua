local M = {}

-- Import required modules
local config = require("nudge-two-hats.config")
local buffer = require("nudge-two-hats.buffer")
local api = require("nudge-two-hats.api")
local utils = require("nudge-two-hats.utils")

-- Function to update configuration
function M.update_config(new_config)
  config = new_config
end

-- Function to stop notification timer for a buffer
function M.stop_notification_timer(buf, state)
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] stop_notification_timer: Called for buf %d. Current timer ID: %s", buf, tostring(state.timers.notification[buf] or "nil")))
  end
  local timer_id = state.timers.notification[buf]
  if timer_id then
    local ok, err = pcall(vim.fn.timer_stop, timer_id)
    if not ok then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] ERROR pcalling timer_stop for notification timer ID %s, buf %d: %s", tostring(timer_id), buf, tostring(err)))
      end
    end
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 通知タイマー停止: バッファ %d, タイマーID %d",
        buf, timer_id))
    end
    if config.debug_mode then
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
      if log_file then
        log_file:write(string.format("Stopped notification timer for buffer %d with ID %d at %s\n",
          buf, timer_id, os.date("%Y-%m-%d %H:%M:%S")))
        log_file:close()
      end
    end
    local old_timer_id = timer_id
    state.timers.notification[buf] = nil
    if state.timers.notification_start_time and state.timers.notification_start_time[buf] then
      state.timers.notification_start_time[buf] = nil
    end
    return timer_id
  end
  return nil
end

-- Function to stop virtual text timer for a buffer
function M.stop_virtual_text_timer(buf, state)
  if config.debug_mode then
    local current_timer_id = state.timers and state.timers.virtual_text and state.timers.virtual_text[buf]
    print(string.format("[Nudge Two Hats Debug Timer] stop_virtual_text_timer: Called for buf %d. Current timer ID: %s", buf, tostring(current_timer_id or "nil")))
  end
  state.timers = state.timers or {}
  state.timers.virtual_text = state.timers.virtual_text or {}
  local timer_id = state.timers.virtual_text[buf]
  if timer_id then
    local ok, err = pcall(vim.fn.timer_stop, timer_id)
    if not ok then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] ERROR pcalling timer_stop for virtual text timer ID %s, buf %d: %s", tostring(timer_id), buf, tostring(err)))
      end
    end
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Stopped virtual text timer for buffer %d with ID %d",
        buf, timer_id))
    end
    if config.debug_mode then
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
      if log_file then
        log_file:write(string.format("Stopped virtual text timer for buffer %d with ID %d at %s\n",
          buf, timer_id, os.date("%Y-%m-%d %H:%M:%S")))
        log_file:close()
      end
    end
    local old_timer_id = timer_id
    state.timers.virtual_text[buf] = nil
    return old_timer_id
  end
  return nil
end

-- Function to pause virtual text timer for a buffer
function M.pause_virtual_text_timer(buf, state)
  if not state.timers or not state.timers.virtual_text or not state.timers.virtual_text[buf] then
    return
  end

  if not state.timers.paused_virtual_text then
    state.timers.paused_virtual_text = {}
  end

  -- Store the timer ID and mark as paused
  state.timers.paused_virtual_text[buf] = state.timers.virtual_text[buf]

  -- Stop the actual timer
  local timer_id = state.timers.virtual_text[buf]
  if timer_id then
    local ok, err = pcall(vim.fn.timer_stop, timer_id)
    if not ok and config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] ERROR stopping virtual text timer for pause: %s", tostring(err)))
    end
    state.timers.virtual_text[buf] = nil

    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] Paused virtual text timer for buf %d (timer ID: %d)", buf, timer_id))
    end
  end
end

-- Function to resume virtual text timer for a buffer
function M.resume_virtual_text_timer(buf, state, stop_virtual_text_timer_func, display_virtual_text_func)
  if not state.timers or not state.timers.paused_virtual_text or not state.timers.paused_virtual_text[buf] then
    return
  end

  -- Clear the paused state
  state.timers.paused_virtual_text[buf] = nil

  -- Update last cursor move time
  state.last_cursor_move_time = state.last_cursor_move_time or {}
  state.last_cursor_move_time[buf] = os.time()

  -- Restart the virtual text timer
  M.start_virtual_text_timer(buf, "resume", state, display_virtual_text_func)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] Resumed virtual text timer for buf %d", buf))
  end
end

-- Function to pause notification timer for a buffer
function M.pause_notification_timer(buf, state)
  if not state.timers or not state.timers.notification or not state.timers.notification[buf] then
    return
  end

  if not state.timers.paused_notification then
    state.timers.paused_notification = {}
  end

  -- Store the timer ID and mark as paused
  state.timers.paused_notification[buf] = state.timers.notification[buf]

  -- Stop the actual timer
  local timer_id = state.timers.notification[buf]
  if timer_id then
    local ok, err = pcall(vim.fn.timer_stop, timer_id)
    if not ok and config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] ERROR stopping notification timer for pause: %s", tostring(err)))
    end
    state.timers.notification[buf] = nil

    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] Paused notification timer for buf %d (timer ID: %d)", buf, timer_id))
    end
  end
end

-- Function to resume notification timer for a buffer
function M.resume_notification_timer(buf, state, stop_notification_timer_func)
  if not state.timers or not state.timers.paused_notification or not state.timers.paused_notification[buf] then
    return
  end

  -- Clear the paused state
  state.timers.paused_notification[buf] = nil

  -- Update last cursor move time
  state.last_cursor_move_time = state.last_cursor_move_time or {}
  state.last_cursor_move_time[buf] = os.time()

  -- Restart the notification timer
  M.start_notification_timer(buf, "resume", state, stop_notification_timer_func)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] Resumed notification timer for buf %d", buf))
  end
end

-- Function to check if cursor has been idle for too long
function M.check_cursor_idle(buf, state)
  if not state.last_cursor_move_time or not state.last_cursor_move_time[buf] then
    return false
  end

  local current_time = os.time()
  local last_move_time = state.last_cursor_move_time[buf]
  local idle_time = current_time - last_move_time

  return idle_time >= config.cursor_idle_threshold_seconds
end

-- Function to start notification timer for a buffer (for API requests)
function M.start_notification_timer(buf, event_name, state, stop_notification_timer_func)
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: Called for buf %d from event %s. Current timer ID for buf: %s", buf, event_name or "unknown", tostring(state.timers.notification[buf] or "nil")))
  end
  if not state.enabled then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: Not enabled for buf %d. Returning.", buf))
    end
    return
  end
  -- Check if buffer is valid and current
  if not utils.is_buffer_valid_and_current(buf) then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: buf %d is not valid or current. Returning.", buf))
    end
    return
  end
  -- Removed the existing timer check block as per instructions.
  -- The call to stop_notification_timer_func(buf) is now unconditional before starting a new timer.
  local buffer_content = ""
  if vim.api.nvim_buf_is_valid(buf) then
    vim.cmd("checktime " .. buf)
    -- Get the entire buffer content
    buffer_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    -- Initialize buffer content storage if needed (for backward compatibility)
    if not state.buf_content_by_filetype[buf] then
      state.buf_content_by_filetype[buf] = {}
    end
    -- Get filetypes and update content
    local filetypes = utils.get_buffer_filetypes(buf, state)
    utils.update_buffer_content(buf, buffer_content, filetypes, state)

    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] タイマー開始時にバッファ内容を保存: filetypes=%s, サイズ=%d文字",
        table.concat(filetypes, ", "), #buffer_content))
    end
  end
  -- Reset the start time for this buffer
  if not state.timers.notification_start_time then
    state.timers.notification_start_time = {}
  end
  state.timers.notification_start_time[buf] = os.time()
  -- Stop any existing notification timer that might be invalid
  stop_notification_timer_func(buf)
  if config.debug_mode then
    local log_file = io.open("/tmp/nudge_two_hats_notification_debug.log", "a")
    if log_file then
      log_file:write("=== " .. event_name .. " triggered notification timer start at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:close()
    end
  end
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 通知タイマー開始: バッファ %d, イベント %s", buf, event_name)) -- Existing log
    print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: Starting new timer for buf %d. Interval: %d ms.", buf, config.notify_interval_seconds * 1000))
  end
  -- Create a recursive notification timer function that continues to run regardless of cursor movement
  local function create_notification_timer_callback(target_buf, target_state, target_config, target_stop_func, target_buffer_module, target_api_module)
    local callback_func
    callback_func = function()
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Notification timer callback: Fired for buf %d. Timer ID that fired: %s", target_buf, tostring(target_state.timers.notification[target_buf] or "original_id_unknown")))
      end
      if not vim.api.nvim_buf_is_valid(target_buf) or not target_state.enabled then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Notification timer callback: Buf %d invalid or plugin disabled. Not rescheduling.", target_buf))
        end
        target_state.timers.notification[target_buf] = nil
        return
      end

      -- Check if cursor has been idle for too long
      if M.check_cursor_idle(target_buf, target_state) then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Cursor idle detected for buf %d. Pausing notification timer.", target_buf))
        end
        M.pause_notification_timer(target_buf, target_state)
        return -- Don't proceed with API call or reschedule
      end

      vim.cmd("checktime " .. target_buf)
      local original_content, current_diff, current_diff_filetype = target_buffer_module.get_buf_diff(target_buf, target_state)

      if not current_diff then
        if target_config.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Notification timer: No actual diff for buf %d. Creating context diff.", target_buf))
        end
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        local cursor_row = cursor_pos[1]

        current_diff, _ = utils.create_context_diff(target_buf, cursor_row, 20)

        if target_state.buf_filetypes[target_buf] then
          current_diff_filetype = string.gmatch(target_state.buf_filetypes[target_buf], "[^,]+")() -- Get first filetype
        else
          current_diff_filetype = vim.api.nvim_buf_get_option(target_buf, "filetype")
        end
        if not current_diff_filetype or current_diff_filetype == "" then
          current_diff_filetype = "text" -- Default
        end
        if target_config.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Notification context diff created for buf %d. Filetype: %s. Diff preview: %s", target_buf, current_diff_filetype, string.sub(current_diff, 1, 100)))
        end
      end

      -- Check interval for notification API calls
      local current_time = os.time()
      if not target_state.last_api_call_notification then
        target_state.last_api_call_notification = 0
      end

      -- Always reschedule the next notification timer regardless of API call
      if vim.api.nvim_buf_is_valid(target_buf) and target_state.enabled then
        local next_timer_id = vim.fn.timer_start(target_config.notify_interval_seconds * 1000, callback_func)
        target_state.timers.notification[target_buf] = next_timer_id
        if target_config.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Notification timer rescheduled for buf %d. New Timer ID: %s", target_buf, tostring(next_timer_id)))
        end
      else
        target_state.timers.notification[target_buf] = nil
      end

      -- Now current_diff will always exist. Proceed with the API call.
      if target_config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 通知タイマー発火 - 前回のAPI呼び出し(通知): %s, 現在時刻: %s, 経過: %d秒",
          os.date("%c", target_state.last_api_call_notification),
          os.date("%c", current_time),
          (current_time - target_state.last_api_call_notification)))
      end
      target_state.last_api_call_notification = current_time
      if target_config.debug_mode then
        print("[Nudge Two Hats Debug] 通知を実行します")
        print(string.format("[Nudge Two Hats Debug] Sending diff to Gemini API for filetype: %s. Diff preview: %s", (current_diff_filetype or "unknown"), string.sub(current_diff, 1, 200)))
      end
      local prompt = target_buffer_module.get_prompt_for_buffer(target_buf, target_state, "notification")
      local purpose = target_buffer_module.get_purpose_for_buffer(target_buf, target_state, "notification")
      target_state.context_for = "notification"
      if target_config.debug_mode then
        print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します (通知用)")
        print("[Nudge Two Hats Debug] context_for: " .. target_state.context_for)
        print("[Nudge Two Hats Debug] prompt preview: " .. (prompt and string.sub(prompt, 1, 100) or "nil"))
        print("[Nudge Two Hats Debug] purpose: " .. (purpose or "nil"))
      end
      target_api_module.get_gemini_advice(current_diff, function(advice)
        if target_config.debug_mode then
          print("[Nudge Two Hats Debug] 通知用APIコールバック実行: " .. (advice or "アドバイスなし"))
        end
        if advice then -- Store advice if received
          target_state.notifications = target_state.notifications or {}
          target_state.notifications.last_advice = target_state.notifications.last_advice or {}
          target_state.notifications.last_advice[target_buf] = advice
        end
        local title = "Nudge Two Hats"
        if target_state.selected_hat then
          title = target_state.selected_hat
        end
        if target_config.debug_mode then
          print("[Nudge Two Hats Debug] " .. title .. ": " .. advice)
        else
          vim.notify(advice, vim.log.levels.INFO, { title = title, icon = "🎩" })
        end
        if target_config.debug_mode then
          print("\n=== Nudge Two Hats 通知 ===")
          print(advice)
          print("==========================")
        end
        if original_content then
          target_state.buf_content_by_filetype[target_buf] = target_state.buf_content_by_filetype[target_buf] or {}
          local callback_filetypes = {}
          if target_state.buf_filetypes[target_buf] then
            for ft_item in string.gmatch(target_state.buf_filetypes[target_buf], "[^,]+") do table.insert(callback_filetypes, ft_item) end
          else
            local current_ft = vim.api.nvim_buf_get_option(target_buf, "filetype")
            if current_ft and current_ft ~= "" then table.insert(callback_filetypes, current_ft) end
          end
          if #callback_filetypes > 0 then
            for _, ft_item in ipairs(callback_filetypes) do target_state.buf_content_by_filetype[target_buf][ft_item] = original_content end
          else
            target_state.buf_content_by_filetype[target_buf]["_default"] = original_content
          end
          target_state.buf_content[target_buf] = original_content
          if target_config.debug_mode then
            print("[Nudge Two Hats Debug] Notification API callback: Buffer content state updated with original_content.")
          end
        end
      end, prompt, purpose, target_state)
    end
    return callback_func
  end

  -- Create and start the notification timer
  local notification_callback = create_notification_timer_callback(buf, state, config, stop_notification_timer_func, buffer, api)
  state.timers.notification[buf] = vim.fn.timer_start(config.notify_interval_seconds * 1000, notification_callback)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: Successfully set new timer for buf %d. New Timer ID: %s. Stored ID in state: %s", buf, tostring(state.timers.notification[buf]), tostring(state.timers.notification[buf])))
  end
  return state.timers.notification[buf]
end

-- Function to stop both timers for a buffer
function M.stop_timer(buf, state, stop_notification_timer_func, stop_virtual_text_timer_func)
  local notification_timer_id = nil
  local virtual_text_timer_id = nil

  -- Stop notification timer if function provided
  if stop_notification_timer_func then
    notification_timer_id = stop_notification_timer_func(buf)
  end

  -- Stop virtual text timer if function provided
  if stop_virtual_text_timer_func then
    virtual_text_timer_id = stop_virtual_text_timer_func(buf)
  end

  -- Return the notification timer ID (as expected by the test)
  return notification_timer_id
end

-- Function to start virtual text timer for a buffer (for display)
function M.start_virtual_text_timer(buf, event_name, state, display_virtual_text_func)
  if config.debug_mode then
    local current_timer_id = state.timers and state.timers.virtual_text and state.timers.virtual_text[buf]
    print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Called for buf %d from event %s. Current timer ID for buf: %s", buf, event_name or "unknown", tostring(current_timer_id or "nil")))
  end
  if not state.enabled then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Not enabled for buf %d. Returning.", buf))
    end
    return
  end
  if not utils.is_buffer_valid_and_current(buf) then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: buf %d is not valid or current. Returning.", buf))
    end
    return
  end

  state.timers = state.timers or {}
  state.timers.virtual_text = state.timers.virtual_text or {}
  M.stop_virtual_text_timer(buf, state) -- Stop any existing timer first

  local function make_virtual_text_timer_callback(current_buf_arg, current_state_arg, current_config_arg, current_display_func_arg, current_buffer_module_arg, current_api_module_arg)
    local callback_func -- Forward declaration for recursion
    callback_func = function()
      if not vim.api.nvim_buf_is_valid(current_buf_arg) or not current_state_arg.enabled then
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer: Buf %d invalid or plugin disabled. Not rescheduling.", current_buf_arg))
        end
        current_state_arg.timers.virtual_text[current_buf_arg] = nil
        return
      end

      if current_config_arg.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer callback: Fired for buf %d.", current_buf_arg))
      end

      -- Check if cursor has been idle for too long
      if M.check_cursor_idle(current_buf_arg, current_state_arg) then
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Cursor idle detected for buf %d. Pausing virtual text timer.", current_buf_arg))
        end
        M.pause_virtual_text_timer(current_buf_arg, current_state_arg)
        return -- Don't proceed with API call or reschedule
      end

      local current_pos = vim.fn.getcurpos()
      local cursor_moved = true -- Assume cursor moved by default
      if current_state_arg.last_cursor_pos and current_state_arg.last_cursor_pos[current_buf_arg] then
        if current_pos[2] == current_state_arg.last_cursor_pos[current_buf_arg][2] and -- line
           current_pos[3] == current_state_arg.last_cursor_pos[current_buf_arg][3] then -- col
          cursor_moved = false
        end
      end

      current_state_arg.virtual_text = current_state_arg.virtual_text or {}
      current_state_arg.virtual_text.is_displayed = current_state_arg.virtual_text.is_displayed or {}

      if not cursor_moved then
        if current_state_arg.virtual_text.is_displayed[current_buf_arg] then
          if current_config_arg.debug_mode then
            print(string.format("[Nudge Two Hats Debug Timer] Cursor static AND virtual text displayed for buf %d. Stopping timer.", current_buf_arg))
          end
          M.stop_virtual_text_timer(current_buf_arg, current_state_arg) -- Stop the timer
          return -- Do not proceed to API call or reschedule
        else
          if current_config_arg.debug_mode then
            print(string.format("[Nudge Two Hats Debug Timer] Cursor static, virtual text NOT displayed for buf %d. Proceeding to API call check.", current_buf_arg))
          end
          -- Proceed to API call logic
        end
      else -- Cursor has moved
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Cursor MOVED for buf %d. Clearing display flag, proceeding to API call check.", current_buf_arg))
        end
        current_state_arg.virtual_text.is_displayed[current_buf_arg] = false -- Clear display flag
        -- Proceed to API call logic
      end

      -- Update last cursor position AFTER checking for movement
      current_state_arg.last_cursor_pos = current_state_arg.last_cursor_pos or {}
      current_state_arg.last_cursor_pos[current_buf_arg] = current_pos

      local current_time = os.time()
      if not current_state_arg.last_api_call_virtual_text then
        current_state_arg.last_api_call_virtual_text = 0
      end

      -- API Call Interval Check (only if we haven't returned already)
      if (current_time - current_state_arg.last_api_call_virtual_text) < current_config_arg.virtual_text_interval_seconds then
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] API interval not met for buf %d. Rescheduling timer.", current_buf_arg))
        end
        if vim.api.nvim_buf_is_valid(current_buf_arg) and current_state_arg.enabled then
          local next_timer_id = vim.fn.timer_start(current_config_arg.virtual_text_interval_seconds * 1000, callback_func)
          current_state_arg.timers.virtual_text[current_buf_arg] = next_timer_id
        else
          current_state_arg.timers.virtual_text[current_buf_arg] = nil
        end
        return
      end

      -- Proceed with API Call
      if current_config_arg.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Proceeding with API call for buf %d.", current_buf_arg))
      end
      vim.cmd("checktime " .. current_buf_arg)
      local original_content, current_diff, current_diff_filetype = current_buffer_module_arg.get_buf_diff(current_buf_arg, current_state_arg)

      if not current_diff then
        -- Create context diff if no actual diff (logic remains similar)
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] No actual diff for buf %d. Creating context diff.", current_buf_arg))
        end
        local temp_cursor_pos = vim.api.nvim_win_get_cursor(0)
        local temp_cursor_row = temp_cursor_pos[1]

        current_diff, _ = utils.create_context_diff(current_buf_arg, temp_cursor_row, 20)
        if current_state_arg.buf_filetypes[current_buf_arg] then
          current_diff_filetype = string.gmatch(current_state_arg.buf_filetypes[current_buf_arg], "[^,]+")()
        else
          current_diff_filetype = vim.api.nvim_buf_get_option(current_buf_arg, "filetype")
        end
        if not current_diff_filetype or current_diff_filetype == "" then current_diff_filetype = "text" end
      end

      current_state_arg.last_api_call_virtual_text = current_time
      current_state_arg.context_for = "virtual_text"
      local prompt = current_buffer_module_arg.get_prompt_for_buffer(current_buf_arg, current_state_arg, "virtual_text")
      local purpose = current_buffer_module_arg.get_purpose_for_buffer(current_buf_arg, current_state_arg, "virtual_text")

      current_api_module_arg.get_gemini_advice(current_diff, function(advice)
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] API callback: Received advice for buf %d: %s", current_buf_arg, advice or "nil"))
        end
        if advice then
          current_state_arg.virtual_text.last_advice = current_state_arg.virtual_text.last_advice or {}
          current_state_arg.virtual_text.last_advice[current_buf_arg] = advice
          current_display_func_arg(current_buf_arg, advice) -- This should set is_displayed and stop the timer
          -- DO NOT reschedule timer here if advice is received, as display_virtual_text should handle timer stop.
        else
          -- No advice received, or API call failed. Reschedule timer to try again later.
          if vim.api.nvim_buf_is_valid(current_buf_arg) and current_state_arg.enabled then
            if current_config_arg.debug_mode then
              print(string.format("[Nudge Two Hats Debug Timer] No advice from API for buf %d. Rescheduling timer.", current_buf_arg))
            end
            local next_timer_id = vim.fn.timer_start(current_config_arg.virtual_text_interval_seconds * 1000, callback_func)
            current_state_arg.timers.virtual_text[current_buf_arg] = next_timer_id
          else
            current_state_arg.timers.virtual_text[current_buf_arg] = nil
          end
        end
      end, prompt, purpose, current_state_arg)
    end -- This 'end' closes the 'if (current_time - ...)' block for API interval check
    return callback_func
  end

  local timer_callback = make_virtual_text_timer_callback(buf, state, config, display_virtual_text_func, buffer, api)

  if config.debug_mode then
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      local event_info = event_name and (" triggered by " .. event_name) or ""
      log_file:write("=== Virtual text timer INITIAL start" .. event_info .. " at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:close()
    end
    print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Starting INITIAL self-rescheduling timer for buf %d. Interval: %d ms.", buf, config.virtual_text_interval_seconds * 1000))
  end

  state.timers.virtual_text[buf] = vim.fn.timer_start(config.virtual_text_interval_seconds * 1000, timer_callback)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Successfully set INITIAL self-rescheduling timer for buf %d. New Timer ID: %s", buf, tostring(state.timers.virtual_text[buf])))
  end
  return state.timers.virtual_text[buf]
end

return M
