local M = {}

-- Import required modules
local config = require("nudge-two-hats.config")
local buffer = require("nudge-two-hats.buffer")
local api = require("nudge-two-hats.api")

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
  -- Check if this is the current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: buf %d is not current buffer %d. Returning.", buf, current_buf))
    end
    return
  end
  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(buf) then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: buf %d is not valid. Returning.", buf))
    end
    return
  end
  -- Removed the existing timer check block as per instructions.
  -- The call to stop_notification_timer_func(buf) is now unconditional before starting a new timer.
  local current_content = ""
  if vim.api.nvim_buf_is_valid(buf) then
    vim.cmd("checktime " .. buf)
    -- Get the entire buffer content
    current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    -- Initialize buffer content storage if needed (for backward compatibility)
    if not state.buf_content_by_filetype[buf] then
      state.buf_content_by_filetype[buf] = {}
    end
    -- Get filetypes for this buffer
    local filetypes = {}
    if state.buf_filetypes[buf] then
      for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
        table.insert(filetypes, filetype)
      end
    end
    -- If no stored filetypes, use the current buffer's filetype
    if #filetypes == 0 then
      local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
      if current_filetype and current_filetype ~= "" then
        table.insert(filetypes, current_filetype)
      else
        table.insert(filetypes, "text")  -- Default to text if no filetype
      end
    end
    -- Store the content for each filetype (for backward compatibility)
    for _, filetype in ipairs(filetypes) do
      state.buf_content_by_filetype[buf][filetype] = current_content
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] タイマー開始時にバッファ内容を保存: filetype=%s, サイズ=%d文字",
          filetype, #current_content))
      end
    end
    state.buf_content[buf] = current_content
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
  -- Create a new notification timer with notify_interval_seconds (in seconds)
  state.timers.notification[buf] = vim.fn.timer_start(config.notify_interval_seconds * 1000, function()
    -- local debug_file = io.open("/tmp/nudge_notification_fired.log", "a") -- Keep this commented or remove if not essential for debugging this specific part
    -- if debug_file then
    --   local current_timer_id_in_state = "unknown"
    --   if state and state.timers and state.timers.notification and state.timers.notification[buf] then
    --     current_timer_id_in_state = tostring(state.timers.notification[buf])
    --   end
    --   debug_file:write(string.format("%s - Notification timer callback started for buf %s. Current timer ID in state: %s. Expected firing timer ID: %s. config.debug_mode: %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), tostring(buf), current_timer_id_in_state, tostring(state.timers.notification[buf]), tostring(config.debug_mode)))
    --   debug_file:close()
    -- end
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] Notification timer callback: Fired for buf %d. Timer ID that fired: %s", buf, tostring(state.timers.notification[buf] or "original_id_unknown")))
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Notification timer callback: Buf %d is no longer valid. Returning.", buf))
      end
      return
    end
    vim.cmd("checktime " .. buf)
    local content, diff, diff_filetype = buffer.get_buf_diff(buf, state)
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] get_buf_diff結果: バッファ %d, diff %s, filetype %s",
                         buf, diff and "あり" or "なし", diff_filetype or "なし"))
    end
    if not diff then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] diffが検出されなかったため、通知をスキップします")
      end
      return
    end
    local current_time = os.time()
    if not state.last_api_call_notification then
      state.last_api_call_notification = 0
    end
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 通知タイマー発火 - 前回のAPI呼び出し(通知): %s, 現在時刻: %s, 経過: %d秒",
        os.date("%c", state.last_api_call_notification),
        os.date("%c", current_time),
        (current_time - state.last_api_call_notification)))
    end
    state.last_api_call_notification = current_time
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 通知を実行します")
      print("[Nudge Two Hats Debug] Sending diff to Gemini API for filetype: " .. (diff_filetype or "unknown"))
      print(diff)
    end
    local prompt = buffer.get_prompt_for_buffer(buf, state, "notification")
    state.context_for = "notification"
    if config.debug_mode then
      print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します (通知用)")
      print("[Nudge Two Hats Debug] context_for: " .. state.context_for)
    end
    api.get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] 通知用APIコールバック実行: " .. (advice or "アドバイスなし"))
      end
      local title = "Nudge Two Hats"
      if state.selected_hat then
        title = state.selected_hat
      end
      vim.notify(advice, vim.log.levels.INFO, { title = title, icon = "🎩" })
      if config.debug_mode then
        print("\n=== Nudge Two Hats 通知 ===")
        print(advice)
        print("==========================")
      end
      if content then
        state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
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
    end, prompt, config.purpose, state)
  end)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] start_notification_timer: Successfully set new timer for buf %d. New Timer ID: %s. Stored ID in state: %s", buf, tostring(state.timers.notification[buf]), tostring(state.timers.notification[buf])))
  end
  return state.timers.notification[buf]
end

-- Function to stop virtual text timer for a buffer (called by state.stop_timer)
function M.stop_timer(buf, state, stop_notification_timer_func, stop_virtual_text_timer_func)
  -- local notification_timer_id = stop_notification_timer_func(buf) -- This line should be removed or commented out
  local virtual_text_timer_id = stop_virtual_text_timer_func(buf)
  if stop_notification_timer_func then -- Ensure it can still stop notification timer if called that way
    stop_notification_timer_func(buf)
  end
  return virtual_text_timer_id -- Only return the virtual_text_timer_id
end

-- Function to start virtual text timer for a buffer (for display)
function M.start_virtual_text_timer(buf, event_name, state, display_virtual_text_func)
  if config.debug_mode then
    local current_timer_id = state.timers and state.timers.virtual_text and state.timers.virtual_text[buf]
    print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Called for buf %d from event %s. Current timer ID for buf: %s", buf, event_name or "unknown", tostring(current_timer_id or "nil")))
  end
  return state.timers.notification[buf]
end

-- Function to stop virtual text timer for a buffer (called by state.stop_timer)
function M.stop_timer(buf, state, stop_notification_timer_func, stop_virtual_text_timer_func)
  -- local notification_timer_id = stop_notification_timer_func(buf) -- This line should be removed or commented out
  local virtual_text_timer_id = stop_virtual_text_timer_func(buf)
  return virtual_text_timer_id -- Only return the virtual_text_timer_id
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
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: buf %d is not current buffer %d. Returning.", buf, current_buf))
    end
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: buf %d is not valid. Returning.", buf))
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
        current_state_arg.timers.virtual_text[current_buf_arg] = nil -- Ensure timer ID is cleared
        return
      end

      if current_config_arg.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Virtual text SELF-RESCHEDULING timer callback: Fired for buf %d.", current_buf_arg))
      end

      local current_time = os.time()
      if not current_state_arg.last_api_call_virtual_text then
        current_state_arg.last_api_call_virtual_text = 0
      end

      if (current_time - current_state_arg.last_api_call_virtual_text) < current_config_arg.virtual_text_interval_seconds then
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer callback: Interval not yet met for buf %d. Last call: %s, Current: %s. Skipping API call, will reschedule.", current_buf_arg, os.date("%c", current_state_arg.last_api_call_virtual_text), os.date("%c", current_time)))
        end
        -- Even if interval not met for API call, we still reschedule the timer.
        if vim.api.nvim_buf_is_valid(current_buf_arg) and current_state_arg.enabled then
          local next_timer_id = vim.fn.timer_start(current_config_arg.virtual_text_interval_seconds * 1000, callback_func)
          current_state_arg.timers.virtual_text[current_buf_arg] = next_timer_id
          if current_config_arg.debug_mode then
            print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer for buf %d rescheduled (interval not met path). New ID: %s", current_buf_arg, tostring(next_timer_id)))
          end
        else
          current_state_arg.timers.virtual_text[current_buf_arg] = nil
        end
        return
      end

      vim.cmd("checktime " .. current_buf_arg) -- Ensure buffer is up-to-date
      local original_content, current_diff, current_diff_filetype = current_buffer_module_arg.get_buf_diff(current_buf_arg, current_state_arg)

      if not current_diff then
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer: No actual diff for buf %d. Creating context diff.", current_buf_arg))
        end
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        local cursor_row = cursor_pos[1] -- 1-based
        local line_count = vim.api.nvim_buf_line_count(current_buf_arg)
        local context_start_line = math.max(1, cursor_row - 20)
        local context_end_line = math.min(line_count, cursor_row + 20)
        local context_lines = vim.api.nvim_buf_get_lines(current_buf_arg, context_start_line - 1, context_end_line, false)
        
        local diff_lines = {}
        for _, line in ipairs(context_lines) do
          table.insert(diff_lines, "+ " .. line)
        end
        current_diff = string.format("@@ -%d,%d +%d,%d @@\n%s",
                                     context_start_line, 0, -- Indicate 0 lines from old version at this point
                                     context_start_line, #context_lines, -- Indicate new lines added
                                     table.concat(diff_lines, "\n"))

        if current_state_arg.buf_filetypes[current_buf_arg] then
          current_diff_filetype = string.gmatch(current_state_arg.buf_filetypes[current_buf_arg], "[^,]+")() -- Get first filetype
        else
          current_diff_filetype = vim.api.nvim_buf_get_option(current_buf_arg, "filetype")
        end
        if not current_diff_filetype or current_diff_filetype == "" then
          current_diff_filetype = "text" -- Default if no filetype found
        end
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Context diff created for buf %d. Filetype: %s. Diff preview: %s", current_buf_arg, current_diff_filetype, string.sub(current_diff, 1, 100)))
        end
      end

      -- Now, current_diff will always exist (either actual or context-based)
      -- Proceed with the API call logic using current_diff and current_diff_filetype:
      current_state_arg.last_api_call_virtual_text = current_time -- Update timestamp before API call (moved from inside 'if diff then')
      current_state_arg.context_for = "virtual_text"
      local prompt = current_buffer_module_arg.get_prompt_for_buffer(current_buf_arg, current_state_arg, "virtual_text")

      current_api_module_arg.get_gemini_advice(current_diff, function(advice)
        if current_config_arg.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Virtual text API callback: Received advice for buf %d: %s", current_buf_arg, advice or "nil"))
        end
        if advice then
          current_state_arg.virtual_text.last_advice[current_buf_arg] = advice
          current_display_func_arg(current_buf_arg, advice) -- This call might stop the timer ID that just fired
          
          -- Use 'original_content' for updating buffer state
          if original_content then 
            current_state_arg.buf_content_by_filetype[current_buf_arg] = current_state_arg.buf_content_by_filetype[current_buf_arg] or {}
            local callback_filetypes = {}
            if current_state_arg.buf_filetypes[current_buf_arg] then
              for ft_item in string.gmatch(current_state_arg.buf_filetypes[current_buf_arg], "[^,]+") do table.insert(callback_filetypes, ft_item) end
            else
              local current_ft = vim.api.nvim_buf_get_option(current_buf_arg, "filetype")
              if current_ft and current_ft ~= "" then table.insert(callback_filetypes, current_ft) end
            end
            if #callback_filetypes > 0 then
              for _, ft_item in ipairs(callback_filetypes) do current_state_arg.buf_content_by_filetype[current_buf_arg][ft_item] = original_content end
            else
              current_state_arg.buf_content_by_filetype[current_buf_arg]["_default"] = original_content
            end
            current_state_arg.buf_content[current_buf_arg] = original_content
            if current_config_arg.debug_mode then
                print(string.format("[Nudge Two Hats Debug Timer] Updated buffer content state for buf %d using original_content.", current_buf_arg))
            end
          elseif current_config_arg.debug_mode then
             print(string.format("[Nudge Two Hats Debug Timer] original_content was nil for buf %d. Buffer content state not updated from it.", current_buf_arg))
          end
        end
        -- Reschedule after processing the API response (or lack thereof)
        if vim.api.nvim_buf_is_valid(current_buf_arg) and current_state_arg.enabled then
          local next_timer_id = vim.fn.timer_start(current_config_arg.virtual_text_interval_seconds * 1000, callback_func)
          current_state_arg.timers.virtual_text[current_buf_arg] = next_timer_id
          if current_config_arg.debug_mode then
            print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer for buf %d rescheduled (after API call). New ID: %s", current_buf_arg, tostring(next_timer_id)))
          end
        else
          current_state_arg.timers.virtual_text[current_buf_arg] = nil
        end
      end, prompt, current_config_arg.purpose, current_state_arg)
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
