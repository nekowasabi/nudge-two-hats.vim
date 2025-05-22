local M = {}

-- Import required modules
local config = require("nudge-two-hats.config")
local buffer = require("nudge-two-hats.buffer")
local api = require("nudge-two-hats.api")

-- Function to update configuration
function M.update_config(new_config)
  config = new_config
end

-- Function to start virtual text advice timer for a buffer (for API requests)
function M.start_virtual_text_advice_timer(buf, event_name, state, stop_virtual_text_advice_timer_func)
  if not state.enabled then
    return
  end
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  state.timers.virtual_text_advice = state.timers.virtual_text_advice or {}
  if state.timers.virtual_text_advice[buf] then
    local timer_info = vim.fn.timer_info(state.timers.virtual_text_advice[buf])
    if timer_info and #timer_info > 0 then
      return
    end
  end

  stop_virtual_text_advice_timer_func(buf)

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] virtual text advice timer start: buffer %d, event %s", buf, event_name))
  end

  -- Calculate timer interval with a maximum limit to ensure timer works correctly
  local raw_interval = config.virtual_text_min_interval_seconds * 1000
  local interval = math.min(2000, math.max(100, math.floor(raw_interval)))
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 仮想テキストアドバイスタイマー間隔: 計算値=%fミリ秒, 実際に使用する値=%dミリ秒", raw_interval, interval))
  end
  state.timers.virtual_text_advice[buf] = vim.fn.timer_start(interval, function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.cmd("checktime " .. buf)
    local content, diff, diff_filetype = buffer.get_buf_diff(buf, state)
    if not diff then
      return
    end
    local vt_prompt = buffer.get_prompt_for_buffer(buf, state, "virtual_text")
    state.context_for = "virtual_text"
    api.get_gemini_advice(diff, function(advice)
      state.virtual_text.last_advice[buf] = advice
    end, vt_prompt, config.purpose, state)
    if content then
      state.buf_content[buf] = content
    end
  end)

  return state.timers.virtual_text_advice[buf]
end
-- Function to stop notification timer for a buffer
function M.stop_notification_timer(buf, state)
  local timer_id = state.timers.notification[buf]
  if timer_id then
    vim.fn.timer_stop(timer_id)
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
    return old_timer_id
  end
  return nil
end

-- Function to stop virtual text timer for a buffer
function M.stop_virtual_text_timer(buf, state)
  state.timers = state.timers or {}
  state.timers.virtual_text = state.timers.virtual_text or {}
  local timer_id = state.timers.virtual_text[buf]
  if timer_id then
    vim.fn.timer_stop(timer_id)
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

-- Function to stop virtual text advice timer for a buffer
function M.stop_virtual_text_advice_timer(buf, state)
  state.timers = state.timers or {}
  state.timers.virtual_text_advice = state.timers.virtual_text_advice or {}
  local timer_id = state.timers.virtual_text_advice[buf]
  if timer_id then
    vim.fn.timer_stop(timer_id)
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Stopped virtual text advice timer for buffer %d with ID %d",
        buf, timer_id))
    end
    if config.debug_mode then
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
      if log_file then
        log_file:write(string.format("Stopped virtual text advice timer for buffer %d with ID %d at %s\n",
          buf, timer_id, os.date("%Y-%m-%d %H:%M:%S")))
        log_file:close()
      end
    end
    local old_timer_id = timer_id
    state.timers.virtual_text_advice[buf] = nil
    return old_timer_id
  end
  return nil
end

-- Function to start notification timer for a buffer (for API requests)
function M.start_notification_timer(buf, event_name, state, stop_notification_timer_func)
  if not state.enabled then
    return
  end
  -- Check if this is the current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    return
  end
  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- Check if a notification timer is already running for this buffer
  if state.timers.notification[buf] then
    local timer_info = vim.fn.timer_info(state.timers.notification[buf])
    if timer_info and #timer_info > 0 then
      -- Store the start time if not already set
      if not state.timers.notification_start_time then
        state.timers.notification_start_time = {}
      end
      if not state.timers.notification_start_time[buf] then
        state.timers.notification_start_time[buf] = os.time()
      end
      -- Calculate elapsed and remaining time
      local current_time = os.time()
      local elapsed_time = current_time - state.timers.notification_start_time[buf]
      local correction = config.notify_interval_correction or 1
      local total_time = config.notify_min_interval_seconds * correction -- Apply correction factor
      local remaining_time = math.max(0, total_time - elapsed_time)
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 通知タイマーはすでに実行中です: バッファ %d, 経過時間: %.1f秒, 残り時間: %.1f秒",
                           buf, elapsed_time, remaining_time))
      end
      return
    end
  end
  local current_content = ""
  if vim.api.nvim_buf_is_valid(buf) then
    vim.cmd("checktime " .. buf)
    -- Get the entire buffer content
    current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    -- Initialize temp file storage if needed
    if not state.temp_files then
      state.temp_files = {}
    end
    -- Create a consistent temporary file path for this buffer (without timestamp)
    local temp_file_path = string.format("/tmp/nudge_two_hats_buffer_%d.txt", buf)
    -- Delete existing file if it exists (to ensure only one file per buffer)
    if vim.fn.filereadable(temp_file_path) == 1 then
      os.remove(temp_file_path)
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 既存のテンポラリファイルを削除しました: %s", temp_file_path))
      end
    end
    local temp_file = io.open(temp_file_path, "w")
    if temp_file then
      temp_file:write(current_content)
      temp_file:close()
      os.execute("chmod 444 " .. temp_file_path)
      -- Store the temp file path for this buffer
      state.temp_files[buf] = temp_file_path
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] タイマー開始時に元のバッファ内容をテンポラリファイルに保存: バッファ %d, ファイル %s, サイズ=%d文字", 
          buf, temp_file_path, #current_content))
        -- Calculate content hash for comparison
        local content_hash = 0
        for i = 1, #current_content do
          content_hash = (content_hash * 31 + string.byte(current_content, i)) % 1000000007
        end
        print(string.format("[Nudge Two Hats Debug] 元のバッファ内容ハッシュ: %d", content_hash))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] テンポラリファイルの作成に失敗しました: %s", temp_file_path))
      end
    end
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
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      log_file:write("=== " .. event_name .. " triggered notification timer start at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:close()
    end
  end
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 通知タイマー開始: バッファ %d, イベント %s", buf, event_name))
  end
  -- Create a new notification timer with notify_min_interval_seconds (in seconds)
  -- Calculate timer interval with a maximum limit to ensure timer works correctly
  local raw_interval = (config.notify_min_interval_seconds * (config.notify_interval_correction or 1)) * 1000
  local interval = math.min(2000, math.max(100, math.floor(raw_interval)))
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] u901au77e5u30bfu30a4u30deu30fcu9593u9694: u8a08u7b97u5024=%fu30dfu30eau79d2, u5b9fu969bu306bu4f7fu7528u3059u308bu5024=%du30dfu30eau79d2", raw_interval, interval))
  end
  state.timers.notification[buf] = vim.fn.timer_start(interval, function()
    if not vim.api.nvim_buf_is_valid(buf) then
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
    -- Initialize last_api_call if not set
    if not state.last_api_call then
      state.last_api_call = 0
    end
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 通知タイマー発火 - 前回のAPI呼び出し: %s, 現在時刻: %s, 経過: %d秒",
        os.date("%c", state.last_api_call),
        os.date("%c", current_time),
        (current_time - state.last_api_call)))
    end
    state.last_api_call = current_time
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 通知を実行します")
    end
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Sending diff to Gemini API for filetype: " .. (diff_filetype or "unknown"))
      print(diff)
    end
    -- Get the appropriate prompt for this buffer's filetype
    local prompt = buffer.get_prompt_for_buffer(buf, state, "notification")
    -- 通知用のコンテキストを設定
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
      
      -- 仮想テキスト用に別途Gemini APIを呼び出し
      state.context_for = "virtual_text"
      if config.debug_mode then
        print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します (仮想テキスト用)")
      end
      local vt_prompt = buffer.get_prompt_for_buffer(buf, state, "virtual_text")
      api.get_gemini_advice(diff, function(virtual_text_advice)
        if config.debug_mode then
          print("[Nudge Two Hats Debug] 仮想テキスト用APIコールバック実行: " .. (virtual_text_advice or "アドバイスなし"))
          print("\n=== Nudge Two Hats 仮想テキスト ===")
          print(virtual_text_advice)
          print("================================")
        end
        state.virtual_text.last_advice[buf] = virtual_text_advice
      end, state)
      
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
    end, prompt, config.purpose, state)
  end)
  
  return state.timers.notification[buf]
end

-- Function to stop both notification and virtual text timers for a buffer
function M.stop_timer(buf, state, stop_notification_timer_func, stop_virtual_text_timer_func, stop_virtual_text_advice_timer_func)
  local notification_timer_id = stop_notification_timer_func(buf)
  local virtual_text_timer_id = stop_virtual_text_timer_func(buf)
  local virtual_text_advice_timer_id
  if stop_virtual_text_advice_timer_func then
    virtual_text_advice_timer_id = stop_virtual_text_advice_timer_func(buf)
  end
  return notification_timer_id or virtual_text_timer_id or virtual_text_advice_timer_id
end

-- Function to start virtual text timer for a buffer (for display)
function M.start_virtual_text_timer(buf, event_name, state, display_virtual_text_func)
  if not state.enabled then
    return
  end
  -- Check if this is the current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    return
  end
  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(buf) then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Cannot start virtual text timer for invalid buffer %d", buf))
    end
    return
  end
  state.timers = state.timers or {}
  state.timers.virtual_text = state.timers.virtual_text or {}
  -- Stop any existing timer first
  M.stop_virtual_text_timer(buf, state)
  if config.debug_mode then
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      local event_info = event_name and (" triggered by " .. event_name) or ""
      log_file:write("=== Virtual text timer start" .. event_info .. " at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file:write("Buffer: " .. buf .. "\n")
      log_file:close()
    end
  end
  if config.debug_mode then
    local event_str = event_name or "unknown"
    print(string.format("[Nudge Two Hats Debug] virtual textタイマー開始: バッファ %d, イベント %s", buf, event_str))
  end
  -- Calculate timer duration in milliseconds
  local timer_ms = config.virtual_text.idle_time * 60 * 1000
  -- Create a new timer
  -- Calculate timer interval with a maximum limit to ensure timer works correctly
  local raw_interval = timer_ms
  local interval = math.min(3600000, math.max(100, math.floor(raw_interval)))
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 仮想テキストタイマー間隔: 計算値=%fミリ秒, 実際に使用する値=%dミリ秒", raw_interval, interval))
  end
  state.timers.virtual_text[buf] = vim.fn.timer_start(interval, function()
    -- Check if buffer is still valid
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop_virtual_text_timer(buf, state)
      return
    end
    -- Check if we have advice to display
    if not state.virtual_text.last_advice[buf] then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] No advice available for buffer %d", buf))
      end
      return
    end
    -- Check if cursor has been idle long enough
    local current_time = os.time()
    local last_cursor_move_time = state.virtual_text.last_cursor_move[buf] or 0
    local idle_time = current_time - last_cursor_move_time
    local required_idle_time = (config.virtual_text.cursor_idle_delay or 5) * 60
    if idle_time >= required_idle_time then
      display_virtual_text_func(buf, state.virtual_text.last_advice[buf])
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Displaying virtual text for buffer %d after %d seconds of cursor inactivity",
          buf, idle_time))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor not idle long enough: %d seconds (required: %d seconds)",
          idle_time, required_idle_time))
      end
      -- We need to call the init.lua function here
      state.start_virtual_text_timer_callback(buf)
    end
  end)
  if config.debug_mode then
    local event_info = event_name and (" triggered by " .. event_name) or ""
    print(string.format("[Nudge Two Hats Debug] Started virtual text timer for buffer %d with ID %d%s",
      buf, state.timers.virtual_text[buf], event_info))
  end
  if config.debug_mode then
    local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
    if log_file then
      local event_info = event_name and (" triggered by " .. event_name) or ""
      log_file:write(string.format("Started virtual text timer for buffer %d with ID %d%s at %s\n",
        buf, state.timers.virtual_text[buf], event_info, os.date("%Y-%m-%d %H:%M:%S")))
      log_file:close()
    end
  end
  return state.timers.virtual_text[buf]
end

return M
