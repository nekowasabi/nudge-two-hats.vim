local autocmd = {}

local state
local config
local api

function autocmd.setup(shared_state, shared_config, shared_api)
  state = shared_state
  config = shared_config
  api = shared_api
end

function autocmd.create_autocmd(buf)
  local augroup = vim.api.nvim_create_augroup("nudge-two-hats-" .. buf, {})
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  
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
    end
  end
  
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
  for _, filetype in ipairs(filetypes) do
    state.buf_content_by_filetype[buf][filetype] = content
  end
  
  state.buf_content[buf] = content
  
  local current_time = os.time()
  state.virtual_text.last_cursor_move[buf] = current_time
  
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] Initialized buffer %d with filetypes: %s", 
      buf, table.concat(filetypes, ", ")))
  end

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
          state.buf_content_by_filetype[buf] = nil
          vim.api.nvim_del_augroup_by_id(augroup)
          return
        end

        local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        local filetype_match = false
        
        if not state.buf_filetypes[buf] and current_filetype and current_filetype ~= "" then
          state.buf_filetypes[buf] = current_filetype
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] 自動登録：バッファ %d のfiletype (%s) を登録しました", 
              buf, current_filetype))
          end
          filetype_match = true
        elseif state.buf_filetypes[buf] then
          for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
            if filetype == current_filetype then
              filetype_match = true
              break
            end
          end
        end
        
        if not filetype_match then
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] スキップ：現在のfiletype (%s) が登録されたfiletypes (%s) に含まれていません", 
              current_filetype or "nil", state.buf_filetypes[buf] or "nil"))
          end
          return
        end

        local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        
        for _, filetype in ipairs(filetypes) do
          if not state.buf_content_by_filetype[buf] then
            state.buf_content_by_filetype[buf] = {}
          end
          state.buf_content_by_filetype[buf][filetype] = content
        end
        
        state.buf_content[buf] = content
        
        autocmd.start_notification_timer(buf, ctx.event)
      end, 100)
    end,
  })
  
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      autocmd.clear_virtual_text(buf)
      
      autocmd.start_virtual_text_timer(buf, "CursorMoved")
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor moved in buffer %d, cleared virtual text and restarted timer", buf))
      end
      
      if config.debug_mode then
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write(string.format("Cursor moved in buffer %d at %s, cleared virtual text\n", 
            buf, os.date("%Y-%m-%d %H:%M:%S")))
          log_file:close()
        end
      end
    end
  })
  
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      autocmd.clear_virtual_text(buf)
      
      autocmd.start_virtual_text_timer(buf, "CursorMovedI")
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor moved in Insert mode in buffer %d, cleared virtual text and restarted timer", buf))
        
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write(string.format("Cursor moved in Insert mode in buffer %d at %s, cleared virtual text\n", 
            buf, os.date("%Y-%m-%d %H:%M:%S")))
          log_file:close()
        end
      end
    end
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    buffer = buf,
    callback = function()
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] BufWritePost イベント発生: バッファ %d", buf))
        print(string.format("[Nudge Two Hats Debug] ファイル保存時刻: %s", os.date("%Y-%m-%d %H:%M:%S")))
        
        local line_count = vim.api.nvim_buf_line_count(buf)
        local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
        print(string.format("[Nudge Two Hats Debug] バッファ行数: %d, 先頭行: %s", line_count, first_line:sub(1, 30)))
      end
      
      autocmd.start_notification_timer(buf, "BufWritePost")
    end,
  })
  
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      autocmd.clear_virtual_text(buf)
      autocmd.start_notification_timer(buf, "InsertLeave")
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Insert mode exited in buffer %d, cleared virtual text", buf))
      end
      
      local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
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
      autocmd.start_notification_timer(buf, "BufReadPost")
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
      
      local current_buf = vim.api.nvim_get_current_buf()
      if buf ~= current_buf then
        if log_file then
          log_file:write("Buffer " .. buf .. " is not the current buffer (" .. current_buf .. "), skipping timer setup\n\n")
          log_file:close()
        end
        return
      end
      
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
      
      if idle_condition_met and not state.timers.virtual_text[buf] then
        if log_file then
          log_file:close()
        end
        
        autocmd.start_notification_timer(buf, "CursorHold")
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
      autocmd.clear_virtual_text(buf)
      
      vim.api.nvim_del_augroup_by_id(augroup)
      return true
    end,
  })

  autocmd.setup_virtual_text(buf)
end

function autocmd.setup_virtual_text(buf)
  local augroup = vim.api.nvim_create_augroup("nudge-two-hats-virtual-text-" .. buf, {})
  
  state.virtual_text.last_cursor_pos = state.virtual_text.last_cursor_pos or {}
  state.virtual_text.last_cursor_pos[buf] = nil -- Initialize to nil to force update on first move
  
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      local current_pos = vim.api.nvim_win_get_cursor(0)
      local cursor_row = current_pos[1]
      local cursor_col = current_pos[2]
      
      local last_pos = state.virtual_text.last_cursor_pos[buf]
      local cursor_actually_moved = true
      
      if last_pos then
        cursor_actually_moved = (last_pos.row ~= cursor_row or last_pos.col ~= cursor_col)
      end
      
      state.virtual_text.last_cursor_pos[buf] = { row = cursor_row, col = cursor_col }
      
      if config.debug_mode then
        local log_file = io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
        if log_file then
          log_file:write("=== CursorMoved triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
          log_file:write("Buffer: " .. buf .. "\n")
          log_file:write("Current position: row=" .. cursor_row .. ", col=" .. cursor_col .. "\n")
          if last_pos then
            log_file:write("Previous position: row=" .. last_pos.row .. ", col=" .. last_pos.col .. "\n")
          else
            log_file:write("Previous position: nil (first move)\n")
          end
          log_file:write("Cursor actually moved: " .. tostring(cursor_actually_moved) .. "\n")
          log_file:close()
        end
      end
      
      if cursor_actually_moved then
        local old_time = state.virtual_text.last_cursor_move[buf] or 0
        local new_time = os.time()
        state.virtual_text.last_cursor_move[buf] = new_time
        
        if log_file then
          log_file:write("Updated last_cursor_move from " .. old_time .. " to " .. new_time .. "\n")
        end
        
        if state.virtual_text.extmarks[buf] then
          autocmd.clear_virtual_text(buf)
        end
        
        if log_file then
          log_file:write("Cursor moved but not stopping virtual text timer\n")
        end
      else
        if log_file then
          log_file:write("Cursor didn't actually move, not updating last_cursor_move time\n")
        end
      end
      
      if log_file then
        log_file:close()
      end
    end,
  })
end

function autocmd.stop_notification_timer(buf)
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

function autocmd.stop_virtual_text_timer(buf)
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

function autocmd.stop_timer(buf)
  local notification_timer_id = autocmd.stop_notification_timer(buf)
  local virtual_text_timer_id = autocmd.stop_virtual_text_timer(buf)
  
  return notification_timer_id or virtual_text_timer_id
end

function autocmd.start_notification_timer(buf, event_name)
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
  
  if state.timers.notification[buf] then
    local timer_info = vim.fn.timer_info(state.timers.notification[buf])
    if timer_info and #timer_info > 0 then
      if not state.timers.notification_start_time then
        state.timers.notification_start_time = {}
      end
      
      if not state.timers.notification_start_time[buf] then
        state.timers.notification_start_time[buf] = os.time()
      end
      
      local current_time = os.time()
      local elapsed_time = current_time - state.timers.notification_start_time[buf]
      local total_time = config.min_interval  -- Use min_interval directly in seconds
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
    
    current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    
    if not state.temp_files then
      state.temp_files = {}
    end
    
    local temp_file_path = string.format("/tmp/nudge_two_hats_buffer_%d.txt", buf)
    
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
      
      state.temp_files[buf] = temp_file_path
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] タイマー開始時に元のバッファ内容をテンポラリファイルに保存: バッファ %d, ファイル %s, サイズ=%d文字", 
          buf, temp_file_path, #current_content))
        
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
    
    if not state.buf_content_by_filetype[buf] then
      state.buf_content_by_filetype[buf] = {}
    end
    
    local filetypes = {}
    if state.buf_filetypes[buf] then
      for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
        table.insert(filetypes, filetype)
      end
    end
    
    if #filetypes == 0 then
      local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
      if current_filetype and current_filetype ~= "" then
        table.insert(filetypes, current_filetype)
      else
        table.insert(filetypes, "text")  -- Default to text if no filetype
      end
    end
    
    for _, filetype in ipairs(filetypes) do
      state.buf_content_by_filetype[buf][filetype] = current_content
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] タイマー開始時にバッファ内容を保存: filetype=%s, サイズ=%d文字", 
          filetype, #current_content))
      end
    end
    
    state.buf_content[buf] = current_content
  end
  
  if not state.timers.notification_start_time then
    state.timers.notification_start_time = {}
  end
  state.timers.notification_start_time[buf] = os.time()
  
  autocmd.stop_notification_timer(buf)
  
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
  
  state.timers.notification[buf] = vim.fn.timer_start(config.min_interval * 1000, function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    vim.cmd("checktime " .. buf)
    
    local content, diff, diff_filetype = api.get_buf_diff(buf)
    
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
    
    local prompt = api.get_prompt_for_buffer(buf)
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します")
    end
    
    api.get_gemini_advice(diff, function(advice)
      if config.debug_mode then
        print("[Nudge Two Hats Debug] APIコールバック実行: " .. (advice or "アドバイスなし"))
      end
      
      local title = "Nudge Two Hats"
      if api.selected_hat then
        title = api.selected_hat
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
      
    end, prompt, config.purpose)
  end)
end

function autocmd.start_virtual_text_timer(buf, event_name)
  if not state.enabled then
    return
  end
  
  local current_buf = vim.api.nvim_get_current_buf()
  if buf ~= current_buf then
    return
  end
  
  if not vim.api.nvim_buf_is_valid(buf) then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] Cannot start virtual text timer for invalid buffer %d", buf))
    end
    return
  end
  
  state.timers = state.timers or {}
  state.timers.virtual_text = state.timers.virtual_text or {}
  
  autocmd.stop_virtual_text_timer(buf)
  
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
  
  local timer_ms = config.virtual_text.idle_time * 60 * 1000
  
  state.timers.virtual_text[buf] = vim.fn.timer_start(timer_ms, function()
    if not vim.api.nvim_buf_is_valid(buf) then
      autocmd.stop_virtual_text_timer(buf)
      return
    end
    
    if not state.virtual_text.last_advice[buf] then
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] No advice available for buffer %d", buf))
      end
      return
    end
    
    local current_time = os.time()
    local last_cursor_move_time = state.virtual_text.last_cursor_move[buf] or 0
    local idle_time = current_time - last_cursor_move_time
    local required_idle_time = (config.virtual_text.cursor_idle_delay or 5) * 60
    
    if idle_time >= required_idle_time then
      autocmd.display_virtual_text(buf, state.virtual_text.last_advice[buf])
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Displaying virtual text for buffer %d after %d seconds of cursor inactivity", 
          buf, idle_time))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor not idle long enough: %d seconds (required: %d seconds)", 
          idle_time, required_idle_time))
      end
      
      autocmd.start_virtual_text_timer(buf)
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

function autocmd.clear_virtual_text(buf)
  if not state.virtual_text.namespace or not state.virtual_text.extmarks[buf] then
    return
  end
  
  vim.api.nvim_buf_del_extmark(buf, state.virtual_text.namespace, state.virtual_text.extmarks[buf])
  state.virtual_text.extmarks[buf] = nil
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Virtual text cleared")
  end
end

function autocmd.display_virtual_text(buf, advice)
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
  
  autocmd.clear_virtual_text(buf)
  
  autocmd.stop_timer(buf)
  
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

function autocmd.setup_global_events()
  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      
      if not state.enabled then
        return
      end
      
      if state.buf_filetypes[buf] then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: バッファ %d は登録済み", buf))
        end
        
        autocmd.start_notification_timer(buf, "BufEnter")
        autocmd.start_virtual_text_timer(buf, "BufEnter")
      else
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: バッファ %d は未登録", buf))
        end
      end
    end
  })
  
  vim.api.nvim_create_autocmd("BufLeave", {
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      
      if not state.enabled then
        return
      end
      
      if state.buf_filetypes[buf] then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufLeave: バッファ %d のタイマーを停止", buf))
        end
        
        autocmd.stop_notification_timer(buf)
        autocmd.stop_virtual_text_timer(buf)
      else
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufLeave: バッファ %d は未登録", buf))
        end
      end
    end
  })
  
  vim.api.nvim_create_autocmd("VimLeavePre", {
    pattern = "*",
    callback = function()
      if config.debug_mode then
        print("[Nudge Two Hats Debug] VimLeavePre: 一時ファイルをクリーンアップします")
      end
      
      if state.temp_files then
        for buf, file_path in pairs(state.temp_files) do
          if vim.fn.filereadable(file_path) == 1 then
            os.execute("chmod 644 " .. file_path)
            os.remove(file_path)
            
            if config.debug_mode then
              print(string.format("[Nudge Two Hats Debug] 一時ファイルを削除しました: %s", file_path))
            end
          end
        end
        
        state.temp_files = {}
        
        if config.debug_mode then
          print("[Nudge Two Hats Debug] バッファファイルのクリーンアップが完了しました")
        end
      end
    end
  })
end

return autocmd
