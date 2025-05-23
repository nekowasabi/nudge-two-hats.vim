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
  M.stop_virtual_text_timer(buf, state) -- Stop existing timer before starting a new one

  if config.debug_mode then
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      local event_info = event_name and (" triggered by " .. event_name) or ""
      log_file:write("=== Virtual text timer start" .. event_info .. " at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:close()
    end
    print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Starting new RECURRING timer for buf %d. Interval: %d ms.", buf, config.virtual_text_interval_seconds * 1000))
  end

  state.timers.virtual_text[buf] = vim.fn.timer_start(config.virtual_text_interval_seconds * 1000, function()
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug Timer] Virtual text RECURRING timer callback: Fired for buf %d.", buf))
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer callback: Buf %d is no longer valid. Stopping timer.", buf))
      end
      M.stop_virtual_text_timer(buf, state) -- Stop the timer if buffer is invalid
      return
    end

    local current_time = os.time()
    if not state.last_api_call_virtual_text then
      state.last_api_call_virtual_text = 0
    end

    if (current_time - state.last_api_call_virtual_text) < config.virtual_text_interval_seconds then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer callback: Interval not yet met for buf %d. Last call: %s, Current: %s. Skipping API call.", buf, os.date("%c", state.last_api_call_virtual_text), os.date("%c", current_time)))
      end
      return -- Respect the interval for API calls, even if timer fires more often
    end

    vim.cmd("checktime " .. buf) -- Ensure buffer is up-to-date
    local content, diff, diff_filetype = buffer.get_buf_diff(buf, state)

    if diff then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer callback: Diff detected for buf %d. Filetype: %s. Proceeding with API call.", buf, diff_filetype or "unknown"))
        print(diff)
      end
      state.last_api_call_virtual_text = current_time -- Update timestamp before API call
      state.context_for = "virtual_text"
      local prompt = buffer.get_prompt_for_buffer(buf, state, "virtual_text")

      api.get_gemini_advice(diff, function(advice)
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug Timer] Virtual text API callback: Received advice for buf %d: %s", buf, advice or "nil"))
        end
        if advice then
          state.virtual_text.last_advice[buf] = advice
          display_virtual_text_func(buf, advice) -- Call the display function with new advice
          if content then -- Update buffer content after successful API call and advice display
            state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
            local callback_filetypes = {}
            if state.buf_filetypes[buf] then
              for ft_item in string.gmatch(state.buf_filetypes[buf], "[^,]+") do table.insert(callback_filetypes, ft_item) end
            else
              local current_ft = vim.api.nvim_buf_get_option(buf, "filetype")
              if current_ft and current_ft ~= "" then table.insert(callback_filetypes, current_ft) end
            end
            if #callback_filetypes > 0 then
              for _, ft_item in ipairs(callback_filetypes) do state.buf_content_by_filetype[buf][ft_item] = content end
            else
              state.buf_content_by_filetype[buf]["_default"] = content
            end
            state.buf_content[buf] = content
          end
        end
      end, prompt, config.purpose, state)
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Timer] Virtual text timer callback: No diff detected for buf %d. Skipping API call.", buf))
      end
    end
  end, { ["repeat"] = -1 }) -- Set as a repeating timer

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug Timer] start_virtual_text_timer: Successfully set new RECURRING timer for buf %d. New Timer ID: %s", buf, tostring(state.timers.virtual_text[buf])))
  end
  return state.timers.virtual_text[buf]
end

return M
