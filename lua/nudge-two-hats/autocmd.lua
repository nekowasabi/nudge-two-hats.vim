local M = {}

local config = require("nudge-two-hats.config")

function M.update_config(new_config)
  config = new_config
end

-- バッファ監視用の自動コマンドを作成する関数
-- @param buf number バッファID
-- @param state table プラグインの状態を保持するテーブル
-- @param plugin_functions table プラグイン関数（start_notification_timer, clear_virtual_text, start_virtual_text_timer）
function M.create_autocmd(buf, state, plugin_functions)
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
        plugin_functions.start_notification_timer(buf, ctx.event)
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
      plugin_functions.clear_virtual_text(buf)
      -- Restart virtual text timer
      plugin_functions.start_virtual_text_timer(buf, "CursorMoved")
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
      plugin_functions.clear_virtual_text(buf)
      -- Restart virtual text timer
      plugin_functions.start_virtual_text_timer(buf, "CursorMovedI")
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

-- テンポラリファイルをクリーンアップする関数
function M.clear_tempfiles(debug_mode)
  if debug_mode then
    print("[Nudge Two Hats Debug] エディタ終了時にすべてのバッファファイルをクリーンアップします")
  end
  -- /tmp配下のnudge_two_hats_buffer_*.txtファイルを削除
  local result = vim.fn.system("find /tmp -name 'nudge_two_hats_buffer_*.txt' -type f -delete")
  if debug_mode then
    print("[Nudge Two Hats Debug] バッファファイルのクリーンアップが完了しました")
  end
end

-- BufLeave自動コマンドのコールバック関数
function M.buf_leave_callback(state, plugin_functions)
  local buf = vim.api.nvim_get_current_buf()
  -- Stop notification timer
  local notification_timer_id = plugin_functions.stop_notification_timer(buf)
  -- Stop virtual text timer
  local virtual_text_timer_id = plugin_functions.stop_virtual_text_timer(buf)
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

  -- Delete the temporary file for this buffer
  if state.temp_files and state.temp_files[buf] then
    local temp_file_path = state.temp_files[buf]
    if vim.fn.filereadable(temp_file_path) == 1 then
      os.remove(temp_file_path)
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] BufLeave: Deleted temp file for buffer %d at %s", buf, temp_file_path))
      end
    end
    state.temp_files[buf] = nil
  end
end

-- BufEnter自動コマンドのコールバック関数
function M.buf_enter_callback(state, plugin_functions)
  local buf = vim.api.nvim_get_current_buf()
  -- プラグインが有効な場合のみupdatetimeを設定
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
      -- アドバイス表示用のvirtual textタイマーを開始
      plugin_functions.start_virtual_text_timer(buf)
      if config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] BufEnter: Restarted virtual text timer for buffer %d", buf))
      end

      -- Create baseline temporary file for the buffer
      local current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      local temp_file_path = string.format("/tmp/nudge_two_hats_buffer_%d.txt", buf)
      
      -- Ensure state.temp_files is initialized
      state.temp_files = state.temp_files or {}

      -- Remove existing file if it exists, to ensure a fresh baseline
      if vim.fn.filereadable(temp_file_path) == 1 then
        os.remove(temp_file_path)
      end

      local temp_file = io.open(temp_file_path, "w")
      if temp_file then
        temp_file:write(current_content)
        temp_file:close()
        os.execute("chmod 644 " .. temp_file_path)
        state.temp_files[buf] = temp_file_path
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: Created baseline temp file for buffer %d at %s", buf, temp_file_path))
        end
      else
        if config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: Failed to create baseline temp file for buffer %d at %s", buf, temp_file_path))
        end
      end

      -- Start notification timer as well
      plugin_functions.start_notification_timer(buf, "BufEnter")
    end
  end
end

-- 自動コマンドを設定する関数
function M.setup(config, state, plugin_functions)
  local group = vim.api.nvim_create_augroup("nudge-two-hats-autocmd", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    pattern = "*",
    callback = function()
      M.clear_tempfiles(config.debug_mode)
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    pattern = "*",
    callback = function()
      M.buf_leave_callback(config, state, plugin_functions)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = function()
      M.buf_enter_callback(config, state, plugin_functions)
    end,
  })
end

return M
