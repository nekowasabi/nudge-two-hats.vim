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
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] get_buf_diff開始: バッファ %d, 時刻: %s", buf, os.date("%Y-%m-%d %H:%M:%S")))
    print("[Nudge Two Hats Debug] 保存されたバッファ内容と現在の内容を比較します")
  end
  
  local line_count = vim.api.nvim_buf_line_count(buf)
  local content
  
  if line_count < 1000 then
    content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  else
    local chunks = {}
    local chunk_size = 500
    local total_chunks = math.ceil(line_count / chunk_size)
    
    for i = 0, total_chunks - 1 do
      local start_line = i * chunk_size
      local end_line = math.min((i + 1) * chunk_size, line_count)
      table.insert(chunks, table.concat(vim.api.nvim_buf_get_lines(buf, start_line, end_line, false), "\n"))
    end
    
    content = table.concat(chunks, "\n")
  end
  
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] 現在のバッファ内容: %d文字", #content))
    local content_preview = content:sub(1, 50):gsub("\n", "\\n")
    print(string.format("[Nudge Two Hats Debug] バッファ内容プレビュー: %s...", content_preview))
    -- Calculate content hash for comparison
    local content_hash = 0
    for i = 1, #content do
      content_hash = (content_hash * 31 + string.byte(content, i)) % 1000000007
    end
    print(string.format("[Nudge Two Hats Debug] バッファ内容ハッシュ: %d", content_hash))
  end
  
  -- Get the filetypes for this buffer
  local filetypes = {}
  if state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] バッファ %d の登録済みfiletypes: %s", 
        buf, state.buf_filetypes[buf]))
    end
  else
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] バッファ %d の現在のfiletype: %s", 
          buf, current_filetype))
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] バッファ %d のfiletypeが見つかりません", buf))
      end
    end
  end
  
  if #filetypes == 0 then
    table.insert(filetypes, "_default")
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] filetypeが見つからないため、_defaultを使用します")
    end
  end
  
  -- Initialize buffer content storage if needed
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}
  
  -- Check if this is the first notification
  local first_notification = true
  for _, filetype in ipairs(filetypes) do
    if state.buf_content_by_filetype[buf][filetype] then
      first_notification = false
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 既存のバッファ内容が見つかりました: filetype=%s, サイズ=%d文字", 
          filetype, #state.buf_content_by_filetype[buf][filetype]))
      end
      
      break
    end
  end
  
  local force_diff = false
  local event_name = vim.v.event and vim.v.event.event
  if event_name == "BufWritePost" then
    force_diff = true
    
    if config.debug_mode then
      print("[Nudge Two Hats Debug] BufWritePostイベントのため、強制的にdiffを生成します")
    end
  end
  
  if first_notification and content and content ~= "" then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] 初回通知のためダミーdiffを作成します（カーソル位置周辺のみ）")
    end
    
    local first_filetype = filetypes[1]
    state.buf_content_by_filetype[buf][first_filetype] = ""
    
    -- Get cursor position
    local cursor_pos
    local cursor_line
    
    -- Safely get cursor position
    local status, err = pcall(function()
      cursor_pos = vim.api.nvim_win_get_cursor(0)
      cursor_line = cursor_pos[1]
    end)
    
    if not status then
      cursor_line = 1
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] カーソル位置の取得に失敗しました: %s", err))
      end
    end
    
    -- Calculate range (cursor position ±10 lines)
    local context_lines = 10
    local start_line = math.max(1, cursor_line - context_lines)
    local end_line = math.min(line_count, cursor_line + context_lines)
    local context_line_count = end_line - start_line + 1
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] カーソル位置: %d行目, 範囲: %d-%d行 (合計%d行)", 
        cursor_line, start_line, end_line, context_line_count))
    end
    
    -- Create a diff showing only lines around cursor position
    local diff = string.format("--- a/dummy\n+++ b/current\n@@ -0,0 +1,%d @@\n", context_line_count)
    for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)) do
      diff = diff .. "+" .. line .. "\n"
    end
    
    local context_content = table.concat(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false), "\n")
    state.buf_content_by_filetype[buf][first_filetype] = context_content
    state.buf_content[buf] = context_content
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 初回通知用のコンテキスト: %d文字", #context_content))
      print(string.format("[Nudge Two Hats Debug] 初回通知用のdiff: %d文字", #diff))
    end
    
    return context_content, diff, first_filetype
  end
  
  local old = nil
  local detected_filetype = nil
  
  -- First try to use the temporary file if available
  if state.temp_files and state.temp_files[buf] then
    local temp_file_path = state.temp_files[buf]
    local temp_file = io.open(temp_file_path, "r")
    
    if temp_file then
      old = temp_file:read("*all")
      temp_file:close()
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] テンポラリファイルから元の内容を読み込みました: %s, サイズ=%d文字", 
          temp_file_path, #old))
      end
      
      -- Use the first filetype as the detected filetype
      if #filetypes > 0 then
        detected_filetype = filetypes[1]
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] テンポラリファイルの読み込みに失敗しました: %s", temp_file_path))
      end
    end
  else
    for _, filetype in ipairs(filetypes) do
      if state.buf_content_by_filetype[buf] and state.buf_content_by_filetype[buf][filetype] then
        old = state.buf_content_by_filetype[buf][filetype]
        detected_filetype = filetype
        
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] filetype=%sの内容を使用します", filetype))
        end
        
        break
      end
    end
    
    -- If still no content, try using the buffer content
    if not old and state.buf_content[buf] then
      old = state.buf_content[buf]
      
      if not detected_filetype and #filetypes > 0 then
        detected_filetype = filetypes[1]
      end
      
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] バッファ全体の内容を使用します"))
      end
    end
  end
  
  if old then
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 比較: 古い内容=%d文字, 新しい内容=%d文字", 
        #old, #content))
      
      local old_sample = string.sub(old, 1, 100)
      local new_sample = string.sub(content, 1, 100)
      print(string.format("[Nudge Two Hats Debug] 古い内容(先頭100文字): %s", old_sample))
      print(string.format("[Nudge Two Hats Debug] 新しい内容(先頭100文字): %s", new_sample))
    end
    
    if force_diff or old ~= content then
      local diff = vim.diff(old, content, { result_type = "unified" })
      
      if config.debug_mode then
        if diff then
          print(string.format("[Nudge Two Hats Debug] vim.diffの結果: %d文字", #diff))
          local diff_preview = diff:sub(1, 100):gsub("\n", "\\n")
          print(string.format("[Nudge Two Hats Debug] diff内容プレビュー: %s...", diff_preview))
        else
          print("[Nudge Two Hats Debug] vim.diffの結果: nil")
        end
        
        print(string.format("[Nudge Two Hats Debug] 内容比較結果: old ~= content は %s", 
          tostring(old ~= content)))
      end
      
      if type(diff) == "string" and diff ~= "" then
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] 差分が見つかりました: filetype=%s", detected_filetype))
          print(string.format("[Nudge Two Hats Debug] バッファ内容を更新します: %d文字", #content))
        end
        
        if detected_filetype then
          state.buf_content_by_filetype[buf][detected_filetype] = content
        end
        state.buf_content[buf] = content
        
        -- Delete the temporary file after notification
        if state.temp_files and state.temp_files[buf] then
          local temp_file_path = state.temp_files[buf]
          
          os.execute("chmod 644 " .. temp_file_path)
          os.remove(temp_file_path)
          
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] 通知後にテンポラリファイルを削除しました: %s", temp_file_path))
          end
          
          state.temp_files[buf] = nil
        end
        
        return content, diff, detected_filetype
      elseif force_diff then
        -- For BufWritePost, create a minimal diff if none was found
        local minimal_diff = string.format("--- a/old\n+++ b/current\n@@ -1,1 +1,1 @@\n-%s\n+%s\n", 
          "No changes detected, but file was saved", "File saved at " .. os.date("%c"))
        
        if config.debug_mode then
          print("[Nudge Two Hats Debug] BufWritePostのため、最小限のdiffを生成します")
        end
        
        -- Delete the temporary file after notification
        if state.temp_files and state.temp_files[buf] then
          local temp_file_path = state.temp_files[buf]
          
          os.execute("chmod 644 " .. temp_file_path)
          os.remove(temp_file_path)
          
          if config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] 通知後にテンポラリファイルを削除しました: %s", temp_file_path))
          end
          
          state.temp_files[buf] = nil
        end
        
        return content, minimal_diff, detected_filetype
      end
    else
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] 内容が同一のため、差分なし: filetype=%s", detected_filetype or "unknown"))
      end
    end
  else
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] 比較対象の古い内容が見つかりません: filetype=%s", detected_filetype or "unknown"))
    end
  end
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] 差分が見つかりませんでした。バッファ内容を更新します。")
  end
  
  -- Update buffer content even if no diff was found
  for _, filetype in ipairs(filetypes) do
    state.buf_content_by_filetype[buf][filetype] = content
    
    if config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] バッファ内容を更新しました: filetype=%s, サイズ=%d文字", 
        filetype, #content))
    end
  end
  state.buf_content[buf] = content
  
  return content, nil, nil
end

local selected_hat = nil

local function get_prompt_for_buffer(buf)
  local filetypes = {}
  
  -- Check if we have stored filetypes for this buffer
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
    end
  end
  
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Buffer filetypes: " .. table.concat(filetypes, ", "))
  end
  
  -- Check if we have a specific prompt for any of the filetypes
  for _, filetype in ipairs(filetypes) do
    if filetype and config.filetype_prompts[filetype] then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Using filetype-specific prompt for: " .. filetype)
      end
      
      local filetype_prompt = config.filetype_prompts[filetype]
      
      if type(filetype_prompt) == "string" then
        selected_hat = nil
        return filetype_prompt
      elseif type(filetype_prompt) == "table" then
        local role = filetype_prompt.role or config.default_cbt.role
        local direction = filetype_prompt.direction or config.default_cbt.direction
        local emotion = filetype_prompt.emotion or config.default_cbt.emotion
        local tone = filetype_prompt.tone or config.default_cbt.tone
        local prompt_text = filetype_prompt.prompt
        
        local hats = filetype_prompt.hats or config.default_cbt.hats or {}
        
        if #hats > 0 then
          math.randomseed(os.time())
          selected_hat = hats[math.random(1, #hats)]
          
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Selected hat: " .. selected_hat)
          end
        end
        
        return string.format("I am a %s wearing the %s hat. %s. With %s emotions and a %s tone, I will advise: %s", 
                             role, selected_hat, direction, emotion, tone, prompt_text)
      else
        selected_hat = nil
        return string.format("I am a %s. %s. With %s emotions and a %s tone, I will advise: %s", 
                             role, direction, emotion, tone, prompt_text)
      end
    end
  end
  
  selected_hat = nil
  return config.system_prompt
end

local advice_cache = {}
local advice_cache_keys = {}
local MAX_ADVICE_CACHE_SIZE = 10

local function get_gemini_advice(diff, callback, prompt, purpose)
  local api_key = vim.fn.getenv("GEMINI_API_KEY") or state.api_key
  
  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] API Key: %s", api_key and "設定済み" or "未設定"))
  end
  
  if not api_key then
    local error_msg = translate_message(translations.en.api_key_not_set)
    if config.debug_mode then
      print("[Nudge Two Hats Debug] APIキーが設定されていません")
    end
    vim.notify(error_msg, vim.log.levels.ERROR)
    return
  end

  local cache_key = nil
  if #diff < 10000 then  -- Only cache for reasonably sized diffs
    cache_key = diff .. (prompt or "") .. (purpose or "")
    
    -- Check if we have a cached response
    if advice_cache[cache_key] then
      if config.debug_mode then
        print("[Nudge Two Hats Debug] Using cached API response")
      end
      vim.schedule(function()
        callback(advice_cache[cache_key])
      end)
      return
    end
  end

  local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
  if log_file then
    log_file:write("--- New API Request ---\n")
    log_file:write("Timestamp: " .. os.date() .. "\n")
    log_file:write("API Key: " .. string.sub(api_key, 1, 5) .. "...\n")
    log_file:write("Endpoint: " .. config.api_endpoint .. "\n")
    if prompt then
      log_file:write("Using prompt: " .. prompt .. "\n")
    end
    log_file:close()
  end

  local system_prompt = prompt or config.system_prompt
  
  local purpose_text = purpose or config.purpose
  if purpose_text and purpose_text ~= "" then
    system_prompt = system_prompt .. "\n\nWork purpose: " .. purpose_text
  end
  
  local output_lang = get_language()
  if output_lang == "ja" then
    system_prompt = system_prompt .. string.format("\n必ず日本語で回答してください。%d文字程度の簡潔なアドバイスをお願いします。", config.message_length)
  else
    system_prompt = system_prompt .. string.format("\nPlease respond in English. Provide concise advice in about %d characters.", config.message_length)
  end
  
  local max_diff_size = 10000  -- 10KB is usually enough for context
  local truncated_diff = diff
  if #diff > max_diff_size then
    truncated_diff = string.sub(diff, 1, max_diff_size) .. "\n... (truncated for performance)"
    if config.debug_mode then
      print("[Nudge Two Hats Debug] Diff truncated from " .. #diff .. " to " .. #truncated_diff .. " bytes")
    end
  end
  
  local sanitized_diff = sanitize_text(truncated_diff)
  if config.debug_mode and sanitized_diff ~= truncated_diff then
    print("[Nudge Two Hats Debug] Diff content sanitized for UTF-8 compliance")
  end
  
  local ok, request_data = pcall(vim.fn.json_encode, {
    contents = {
      {
        parts = {
          {
            text = system_prompt .. "\n\n" .. sanitized_diff
          }
        }
      }
    },
    generationConfig = {
      thinkingConfig = {
        thinkingBudget = 0
      },
      temperature = 0.2,
      topK = 40,
      topP = 0.95,
      maxOutputTokens = 1024
    }
  })
  
  if not ok then
    if config.debug_mode then
      print("[Nudge Two Hats Debug] JSON encoding failed: " .. tostring(request_data))
    end
    local error_msg = translate_message(translations.en.api_error)
    vim.notify(error_msg .. ": JSON encoding failed", vim.log.levels.ERROR)
    callback(translate_message(translations.en.api_error))
    return
  end

  local has_plenary, curl = pcall(require, "plenary.curl")
  
  if has_plenary then
    local endpoint = config.api_endpoint:gsub("[<>]", "")
    local full_url = endpoint .. "?key=" .. api_key
    
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using plenary.curl\n")
      log_file:write("Clean endpoint: " .. endpoint .. "\n")
      log_file:write("Full URL (sanitized): " .. string.gsub(full_url, api_key, string.sub(api_key, 1, 5) .. "...") .. "\n")
      log_file:close()
    end
    
    curl.post(full_url, {
      headers = {
        ["Content-Type"] = "application/json",
      },
      body = request_data,
      callback = function(response)
        vim.schedule(function()
          if response.status == 200 and response.body then
            local ok, result
            if vim.json and vim.json.decode then
              ok, result = pcall(vim.json.decode, response.body)
            else
              ok, result = pcall(function() return vim.fn.json_decode(response.body) end)
            end
            
            if ok and result and result.candidates and result.candidates[1] and 
               result.candidates[1].content and result.candidates[1].content.parts and 
               result.candidates[1].content.parts[1] and result.candidates[1].content.parts[1].text then
              local advice = result.candidates[1].content.parts[1].text
              
              if cache_key then
                advice_cache[cache_key] = advice
                table.insert(advice_cache_keys, cache_key)
                
                if #advice_cache_keys > MAX_ADVICE_CACHE_SIZE then
                  local to_remove = table.remove(advice_cache_keys, 1)
                  advice_cache[to_remove] = nil
                end
              end
              
              if config.length_type == "characters" then
                if #advice > config.message_length then
                  advice = safe_truncate(advice, config.message_length)
                end
              else
                local words = {}
                for word in advice:gmatch("%S+") do
                  table.insert(words, word)
                end
                
                if #words > config.message_length then
                  local truncated_words = {}
                  for i = 1, config.message_length do
                    table.insert(truncated_words, words[i])
                  end
                  advice = table.concat(truncated_words, " ")
                end
              end
              
              if config.translate_messages then
                advice = translate_message(advice)
              end
              
              callback(advice)
              
            else
              callback(translate_message(translations.en.api_error))
            end
          else
            local error_msg = translate_message(translations.en.api_error)
            vim.notify(error_msg .. ": " .. (response.body or translate_message(translations.en.unknown_error)), vim.log.levels.ERROR)
            callback(translate_message(translations.en.api_error))
          end
        end)
      end
    })
  else
    local endpoint = config.api_endpoint:gsub("[<>]", "")
    local full_url = endpoint .. "?key=" .. api_key
    local temp_file = "/tmp/nudge_two_hats_request.json"
    
    local req_file = io.open(temp_file, "w")
    if req_file then
      req_file:write(request_data)
      req_file:close()
    end
    
    if log_file then
      log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
      log_file:write("Using curl fallback\n")
      log_file:write("Clean endpoint: " .. endpoint .. "\n")
      log_file:write("Full URL (sanitized): " .. string.gsub(full_url, api_key, string.sub(api_key, 1, 5) .. "...") .. "\n")
      log_file:write("Command: curl -s -X POST " .. endpoint .. "?key=" .. string.sub(api_key, 1, 5) .. "... -H 'Content-Type: application/json' -d @" .. temp_file .. "\n")
      log_file:close()
    end
    
    local curl_command = string.format(
      "curl -s -X POST %s -H 'Content-Type: application/json' -d @%s",
      full_url,
      temp_file
    )
    
    vim.fn.jobstart(curl_command, {
      on_stdout = function(_, data)
        if data and #data > 0 and data[1] ~= "" then
          vim.schedule(function()
            local ok, response
            if vim.json and vim.json.decode then
              ok, response = pcall(vim.json.decode, table.concat(data, "\n"))
            else
              ok, response = pcall(function() return vim.fn.json_decode(table.concat(data, "\n")) end)
            end
            
            if ok and response and response.candidates and response.candidates[1] and 
               response.candidates[1].content and response.candidates[1].content.parts and 
               response.candidates[1].content.parts[1] and response.candidates[1].content.parts[1].text then
              local advice = response.candidates[1].content.parts[1].text
              
              if config.length_type == "characters" then
                if #advice > config.message_length then
                  advice = safe_truncate(advice, config.message_length)
                end
              else
                local words = {}
                for word in advice:gmatch("%S+") do
                  table.insert(words, word)
                end
                
                if #words > config.message_length then
                  local truncated_words = {}
                  for i = 1, config.message_length do
                    table.insert(truncated_words, words[i])
                  end
                  advice = table.concat(truncated_words, " ")
                end
              end
              
              if config.translate_messages then
                advice = translate_message(advice)
              end
              
              callback(advice)
              
            else
              callback(translate_message(translations.en.api_error))
            end
          end)
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 0 and data[1] ~= "" then
          vim.schedule(function()
            local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a")
            if log_file then
              log_file:write("Curl stderr: " .. table.concat(data, "\n") .. "\n")
              log_file:close()
            end
            
            local error_msg = translate_message(translations.en.api_error)
            vim.notify(error_msg .. ": " .. table.concat(data, "\n"), vim.log.levels.ERROR)
          end)
        end
      end,
      on_exit = function(_, code)
        -- Delete the temporary file after API call completes
        if vim.fn.filereadable(temp_file) == 1 then
          vim.fn.delete(temp_file)
          if config.debug_mode then
            print("[Nudge Two Hats Debug] Deleted temporary file: " .. temp_file)
          end
        end
        
        if code ~= 0 then
          vim.schedule(function()
            callback(translate_message(translations.en.api_error))
          end)
        end
      end
    })
  end
end

local function create_autocmd(buf)
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

  -- Set up text change events to trigger notification timer
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

        -- Check if current filetype is in the list of registered filetypes
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
          -- Check if current filetype matches any registered filetype
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
        
        -- Start notification timer for API request
        M.start_notification_timer(buf, ctx.event)
      end, 100)
    end,
  })
  
  -- Set up cursor movement events to track cursor position and clear virtual text
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      M.clear_virtual_text(buf)
      
      -- Restart virtual text timer
      M.start_virtual_text_timer(buf, "CursorMoved")
      
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
  
  -- Set up cursor movement events in Insert mode to clear virtual text
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      state.virtual_text.last_cursor_move[buf] = os.time()
      
      M.clear_virtual_text(buf)
      
      -- Restart virtual text timer
      M.start_virtual_text_timer(buf, "CursorMovedI")
      
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
end

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
    
    local content, diff, diff_filetype = get_buf_diff(buf)
    
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

local function start_notification_timer(buf, event_name)
  M.start_notification_timer(buf, event_name)
end

local function setup_virtual_text(buf)
  -- Store the last cursor position to detect actual movement
  state.virtual_text.last_cursor_pos = state.virtual_text.last_cursor_pos or {}
  state.virtual_text.last_cursor_pos[buf] = nil -- Initialize to nil to force update on first move
  
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      local current_pos = vim.api.nvim_win_get_cursor(0)
      local cursor_row = current_pos[1]
      local cursor_col = current_pos[2]
      
      -- Check if cursor has actually moved from its previous position
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
          M.clear_virtual_text(buf)
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
      
      start_notification_timer(buf, "BufWritePost")
    end,
  })
  
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      
      M.clear_virtual_text(buf)
      start_notification_timer(buf, "InsertLeave")
      
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
