local M = {}

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
function M.buf_leave_callback(config, state, plugin_functions)
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
end

-- BufEnter自動コマンドのコールバック関数
function M.buf_enter_callback(config, state, plugin_functions)
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
    end
  end
end

-- 自動コマンドを設定する関数
function M.setup(config, state, plugin_functions)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    pattern = "*",
    callback = function()
      M.clear_tempfiles(config.debug_mode)
    end
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    pattern = "*",
    callback = function()
      M.buf_leave_callback(config, state, plugin_functions)
    end
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = function()
      M.buf_enter_callback(config, state, plugin_functions)
    end
  })
end

return M
