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

-- Import the API module for all functions
local api = require("nudge-two-hats.api")

-- Import the buffer module
local buffer = require("nudge-two-hats.buffer")

-- Import the autocmd module
local autocmd = require("nudge-two-hats.autocmd")

-- -- Use imported safe_truncate function
-- local safe_truncate = api.safe_truncate

-- local advice_cache = {}
-- local advice_cache_keys = {}
-- local MAX_ADVICE_CACHE_SIZE = 10

-- Stop notification timer for a buffer
function M.stop_notification_timer(buf)
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

-- Stop virtual text timer for a buffer
function M.stop_virtual_text_timer(buf)
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

-- Start notification timer for a buffer (for API requests)
function M.start_notification_timer(buf, event_name)
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
  M.stop_notification_timer(buf)
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
  -- Create a new notification timer with min_interval (in seconds)
  state.timers.notification[buf] = vim.fn.timer_start(config.min_interval * 1000, function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.cmd("checktime " .. buf)
    local buffer = require("nudge-two-hats.buffer")
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
    local prompt = buffer.get_prompt_for_buffer(buf, state)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します")
    end
    api.get_gemini_advice(diff, function(advice)
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
  end)
end

-- Start virtual text timer for a buffer (for display)
function M.start_virtual_text_timer(buf, event_name)
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
  M.stop_virtual_text_timer(buf)
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
  state.timers.virtual_text[buf] = vim.fn.timer_start(timer_ms, function()
    -- Check if buffer is still valid
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop_virtual_text_timer(buf)
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
      M.display_virtual_text(buf, state.virtual_text.last_advice[buf])
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Displaying virtual text for buffer %d after %d seconds of cursor inactivity", 
          buf, idle_time))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] Cursor not idle long enough: %d seconds (required: %d seconds)", 
          idle_time, required_idle_time))
      end
      M.start_virtual_text_timer(buf)
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
    api.update_config(config)
    -- Update buffer module config
    local buffer = require("nudge-two-hats.buffer")
    buffer.update_config(config)
  end
  vim.api.nvim_set_hl(0, "NudgeTwoHatsVirtualText", {
    fg = config.virtual_text.text_color,
    bg = config.virtual_text.background_color,
  })
  state.virtual_text.namespace = vim.api.nvim_create_namespace("nudge-two-hats-virtual-text")
  vim.api.nvim_create_user_command("NudgeTwoHatsToggle", function(args)
    state.enabled = not state.enabled
    local status = state.enabled and api.translate_message(config.translations.en.enabled) or api.translate_message(config.translations.en.disabled)
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
      -- create_autocmd関数をautocmdモジュールから呼び出します
      autocmd.create_autocmd(buf, state, config, {
        start_notification_timer = M.start_notification_timer,
        clear_virtual_text = M.clear_virtual_text,
        start_virtual_text_timer = M.start_virtual_text_timer
      })
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
    vim.notify(api.translate_message(config.translations.en.api_key_set), vim.log.levels.INFO)
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
    autocmd.create_autocmd(buf, state, config, {
      start_notification_timer = M.start_notification_timer,
      clear_virtual_text = M.clear_virtual_text,
      start_virtual_text_timer = M.start_virtual_text_timer
    })
    state.virtual_text.last_cursor_move[buf] = os.time()
    local filetype_str = table.concat(filetypes, ", ")
    local source_str = using_current_filetype and "current buffer" or "specified files"
    vim.notify(string.format("Nudge Two Hats enabled for filetypes: %s (from %s)", filetype_str, source_str), vim.log.levels.INFO)
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
    print(string.format("Virtual text idle time: %s minutes", config.virtual_text.idle_time))
    print(string.format("Notification idle time: %s minutes", config.notification.idle_time))
    print(string.format("Last API call: %s", state.last_api_call or "never"))
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
    local buffer = require("nudge-two-hats.buffer")
    local content, diff, diff_filetype = buffer.get_buf_diff(buf, state)
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
    local prompt = buffer.get_prompt_for_buffer(buf, state)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] get_gemini_adviceを呼び出します")
    end
    api.get_gemini_advice(diff, function(advice)
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
    local prompt = buffer.get_prompt_for_buffer(buf, state)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 強制的に通知処理を実行します")
      print("[Nudge Two Hats Debug] Filetype: " .. (current_filetype or "unknown"))
      print("[Nudge Two Hats Debug] コンテキスト範囲: " .. context_start .. "-" .. context_end .. " 行")
    end
    state.last_api_call = 0
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
      state.virtual_text.last_advice[buf] = advice
    end, prompt, config.purpose)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 通知処理の発火が完了しました")
    end
  end, {})
  
  -- BufEnter autocmdはautocmd.luaに移動しました
  local autocmd = require("nudge-two-hats.autocmd")
  local plugin_functions = {
    stop_notification_timer = M.stop_notification_timer,
    stop_virtual_text_timer = M.stop_virtual_text_timer,
    start_virtual_text_timer = M.start_virtual_text_timer
  }
  autocmd.setup(config, state, plugin_functions)
end

return M
