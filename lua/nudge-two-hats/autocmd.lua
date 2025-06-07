local M = {}

-- Module-level variables
local m_config
local m_state
local m_plugin_functions
local buf_enter_execution_count = 0

-- Keep the original config require for M.update_config and M.clear_tempfiles direct access
local original_config_module = require("nudge-two-hats.config")

function M.update_config(new_config)
  -- This updates the config used by M.clear_tempfiles and potentially other functions
  -- if they are not refactored to use m_config.
  -- For consistency, it should also update m_config if it's already initialized.
  original_config_module = new_config
  if m_config then
    m_config = new_config
  end
end

-- バッファ監視用の自動コマンドを作成する関数
-- @param buf number バッファID
function M.create_autocmd(buf)
  if not m_state or not m_plugin_functions then
    if m_config and m_config.debug_mode then
      print("[Nudge Two Hats Debug] ERROR in create_autocmd: m_state or m_plugin_functions is nil. Buffer: " .. buf)
    end
    return
  end

  local augroup = vim.api.nvim_create_augroup("nudge-two-hats-" .. buf, {})
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local filetypes = {}
  if m_state.buf_filetypes[buf] then
    for filetype in string.gmatch(m_state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  else
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
      m_state.buf_filetypes[buf] = current_filetype
    end
  end
  m_state.buf_content_by_filetype[buf] = m_state.buf_content_by_filetype[buf] or {}
  for _, filetype in ipairs(filetypes) do
    m_state.buf_content_by_filetype[buf][filetype] = content
  end
  m_state.buf_content[buf] = content
  if m_config and m_config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] Initialized buffer %d with filetypes: %s for autocmds.",
      buf, table.concat(filetypes, ", ")))
  end

  -- Set up text change events to trigger notification timer
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "BufWritePost" }, {
    group = augroup,
    buffer = buf,
    callback = function(ctx)
      if not m_state or not m_state.enabled then
        return
      end

      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          if m_state then
            m_state.buf_content[buf] = nil
            m_state.buf_content_by_filetype[buf] = nil
          end
          vim.api.nvim_del_augroup_by_id(augroup)
          return
        end

        -- Check if current filetype is in the list of registered filetypes
        local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        local filetype_match = false
        if m_state and not m_state.buf_filetypes[buf] and current_filetype and current_filetype ~= "" then
          m_state.buf_filetypes[buf] = current_filetype
          if m_config and m_config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] 自動登録：バッファ %d のfiletype (%s) を登録しました",
              buf, current_filetype))
          end
          filetype_match = true
        elseif m_state and m_state.buf_filetypes[buf] then
          -- Check if current filetype matches any registered filetype
          for filetype in string.gmatch(m_state.buf_filetypes[buf], "[^,]+") do
            if filetype == current_filetype then
              filetype_match = true
              break
            end
          end
        end
        if not filetype_match then
          if m_config and m_config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] スキップ：現在のfiletype (%s) が登録されたfiletypes (%s) に含まれていません",
              current_filetype or "nil", m_state and m_state.buf_filetypes[buf] or "nil"))
          end
          return
        end

        local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        if m_state then
          for _, filetype in ipairs(filetypes) do
            if not m_state.buf_content_by_filetype[buf] then
              m_state.buf_content_by_filetype[buf] = {}
            end
            m_state.buf_content_by_filetype[buf][filetype] = content
          end
          m_state.buf_content[buf] = content
        end
        -- Start notification timer for API request
        if not m_plugin_functions or not m_plugin_functions.start_notification_timer then
          if m_config and m_config.debug_mode then
            print("[Nudge Two Hats Debug] ERROR in create_autocmd TextChanged: m_plugin_functions or m_plugin_functions.start_notification_timer is nil. Buffer: " .. buf)
          end
          return
        end
        m_plugin_functions.start_notification_timer(buf, ctx.event)
      end, 100)
    end,
  })
  -- Set up cursor movement events to track cursor position and clear virtual text
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not m_state or not m_state.enabled or not m_plugin_functions then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end

      m_state.virtual_text = m_state.virtual_text or {}
      m_state.virtual_text.is_displayed = m_state.virtual_text.is_displayed or {}
      m_state.virtual_text.is_displayed[buf] = false

      m_plugin_functions.clear_virtual_text(buf)
      m_plugin_functions.start_virtual_text_timer(buf, "CursorMoved_restart")

      if m_config and m_config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Autocmd] CursorMoved in buf %d: Cleared display flag, cleared text, restarted VT timer.", buf))
      end
    end
  })
  -- Set up cursor movement events in Insert mode to clear virtual text
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    buffer = buf,
    callback = function()
      if not m_state or not m_state.enabled or not m_plugin_functions then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end

      m_state.virtual_text = m_state.virtual_text or {}
      m_state.virtual_text.is_displayed = m_state.virtual_text.is_displayed or {}
      m_state.virtual_text.is_displayed[buf] = false

      m_plugin_functions.clear_virtual_text(buf)
      m_plugin_functions.start_virtual_text_timer(buf, "CursorMovedI_restart")

      if m_config and m_config.debug_mode then
        print(string.format("[Nudge Two Hats Debug Autocmd] CursorMovedI in buf %d: Cleared display flag, cleared text, restarted VT timer.", buf))
      end
    end
  })
end

-- テンポラリファイルをクリーンアップする関数
-- This function still uses the original_config_module for debug_mode.
-- If it needs to use m_config, m_config should be checked for nil.
function M.clear_tempfiles()
  local use_debug = (m_config and m_config.debug_mode) or original_config_module.debug_mode
  if use_debug then
    print("[Nudge Two Hats Debug] エディタ終了時にすべてのバッファファイルをクリーンアップします")
  end
  -- /tmp配下のnudge_two_hats_buffer_*.txtファイルを削除
  local result = vim.fn.system("find /tmp -name 'nudge_two_hats_buffer_*.txt' -type f -delete")
  if use_debug then
    print("[Nudge Two Hats Debug] バッファファイルのクリーンアップが完了しました")
  end
end

-- BufLeave自動コマンドのコールバック関数
function M.buf_leave_callback()
  local current_buf_id_leave = vim.api.nvim_get_current_buf()
  if m_state and m_state.buf_enter_processed and m_state.buf_enter_processed[current_buf_id_leave] then
    if m_config and m_config.debug_mode then
      print(string.format("[Nudge Two Hats Debug BufLeave] M.buf_leave_callback: Clearing processed flag for buf %d.", current_buf_id_leave))
    end
    m_state.buf_enter_processed[current_buf_id_leave] = nil
  elseif m_config and m_config.debug_mode then
    -- Log if the flag wasn't set, which might be normal if BufEnter didn't complete for some reason
    print(string.format("[Nudge Two Hats Debug BufLeave] M.buf_leave_callback: No processed flag to clear for buf %d (or m_state/m_state.buf_enter_processed is nil).", current_buf_id_leave))
  end

  if not m_state or not m_plugin_functions then
    if m_config and m_config.debug_mode then
      print("[Nudge Two Hats Debug] ERROR in buf_leave_callback: m_state or m_plugin_functions is nil.")
    end
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local notification_timer_id
  local virtual_text_timer_id

  if not m_plugin_functions or not m_plugin_functions.stop_notification_timer then
    if m_config and m_config.debug_mode then
      print("[Nudge Two Hats Debug] ERROR in buf_leave_callback: m_plugin_functions or m_plugin_functions.stop_notification_timer is nil. Buffer: " .. buf)
    end
  else
    notification_timer_id = m_plugin_functions.stop_notification_timer(buf)
  end

  if not m_plugin_functions or not m_plugin_functions.stop_virtual_text_timer then
    if m_config and m_config.debug_mode then
      print("[Nudge Two Hats Debug] ERROR in buf_leave_callback: m_plugin_functions or m_plugin_functions.stop_virtual_text_timer is nil. Buffer: " .. buf)
    end
  else
    virtual_text_timer_id = m_plugin_functions.stop_virtual_text_timer(buf)
  end

  if notification_timer_id or virtual_text_timer_id then
    if m_config and m_config.debug_mode then
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
  if m_state.original_updatetime then
    vim.o.updatetime = m_state.original_updatetime
  end

  -- Delete the temporary file for this buffer
  if m_state.temp_files and m_state.temp_files[buf] then
    local temp_file_path = m_state.temp_files[buf]
    if vim.fn.filereadable(temp_file_path) == 1 then
      os.remove(temp_file_path)
      if m_config and m_config.debug_mode then
        print(string.format("[Nudge Two Hats Debug] BufLeave: Deleted temp file for buffer %d at %s", buf, temp_file_path))
      end
    end
    m_state.temp_files[buf] = nil
  end
end

-- BufEnter自動コマンドのコールバック関数
function M.buf_enter_callback()
  buf_enter_execution_count = buf_enter_execution_count + 1
  if m_config and m_config.debug_mode then
    local current_buf_id = vim.api.nvim_get_current_buf()
    local event_info = vim.inspect(vim.v.event) -- Inspect vim.v.event
    print(string.format("[Nudge Two Hats Debug BufEnter] M.buf_enter_callback: START. Execution #%d for buf %d. vim.v.event: %s", buf_enter_execution_count, current_buf_id, event_info))
  end

  local current_buf_id_guard = vim.api.nvim_get_current_buf() -- Use a distinct variable name if current_buf_id is used later for other things, or reuse if appropriate.
  if not m_state then -- Ensure m_state is available
      if m_config and m_config.debug_mode then
          print("[Nudge Two Hats Debug BufEnter] ERROR: m_state is nil in M.buf_enter_callback. Cannot implement re-entrancy guard.")
      end
      -- Decide if you should return here or let it proceed without the guard
      -- For now, let's assume m_state should be available from setup.
  else
      m_state.buf_enter_processed = m_state.buf_enter_processed or {} -- Initialize if needed
      if m_state.buf_enter_processed[current_buf_id_guard] then
          if m_config and m_config.debug_mode then
              print(string.format("[Nudge Two Hats Debug BufEnter] M.buf_enter_callback: SKIPPING duplicate processing for buf %d. Execution #%d.", current_buf_id_guard, buf_enter_execution_count))
          end
          -- Also print the END message here before returning, for consistency in START/END pairing
          if m_config and m_config.debug_mode then
            print(string.format("[Nudge Two Hats Debug BufEnter] M.buf_enter_callback: END (skipped duplicate). Execution #%d for buf %d.", buf_enter_execution_count, current_buf_id_guard))
          end
          return -- Exit early
      end
      m_state.buf_enter_processed[current_buf_id_guard] = true
      if m_config and m_config.debug_mode then
          print(string.format("[Nudge Two Hats Debug BufEnter] M.buf_enter_callback: Set processed flag for buf %d. Execution #%d.", current_buf_id_guard, buf_enter_execution_count))
      end
  end

  if not m_config or not m_state or not m_plugin_functions then
    if (m_config and m_config.debug_mode) or (not m_config and original_config_module.debug_mode) then
      print("[Nudge Two Hats Debug] ERROR in buf_enter_callback: m_config, m_state, or m_plugin_functions is nil.")
    end
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  -- プラグインが有効な場合のみupdatetimeを設定
  if m_state.enabled then
    if not m_state.original_updatetime then
      m_state.original_updatetime = vim.o.updatetime
    end
    vim.o.updatetime = 1000
    if m_config.debug_mode then
      print(string.format("[Nudge Two Hats Debug] BufEnter: Switched to buffer %d", buf))
    end
    if m_config.debug_mode then
      local log_file = io.open("/tmp/nudge_two_hats_debug.log", "a") -- Changed log file name
      if log_file then
        log_file:write("=== BufEnter triggered at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
        log_file:write("Current buffer: " .. buf .. "\n")
        log_file:write("Plugin enabled: " .. tostring(m_state.enabled) .. "\n")
        log_file:close()
      end
    end
    if m_state.buf_filetypes[buf] then
      -- Notification timer is started on BufEnter to catch up with potential changes
      m_state.virtual_text = m_state.virtual_text or {}
      m_state.virtual_text.is_displayed = m_state.virtual_text.is_displayed or {}
      m_state.virtual_text.is_displayed[buf] = false

      if m_plugin_functions and m_plugin_functions.clear_virtual_text then
        m_plugin_functions.clear_virtual_text(buf)
      elseif m_config and m_config.debug_mode then
        print("[Nudge Two Hats Debug Autocmd] BufEnter: m_plugin_functions.clear_virtual_text is nil for buf " .. buf)
      end

      if m_plugin_functions and m_plugin_functions.start_virtual_text_timer then
         m_plugin_functions.start_virtual_text_timer(buf, "BufEnter_restart")
         if m_config and m_config.debug_mode then
            print(string.format("[Nudge Two Hats Debug Autocmd] BufEnter for buf %d: Cleared display flag, cleared text, restarted VT timer.", buf))
         end
      else
         if m_config and m_config.debug_mode then
            print("[Nudge Two Hats Debug Autocmd] ERROR in buf_enter_callback: m_plugin_functions.start_virtual_text_timer is nil. Cannot restart VT timer for buf: " .. buf)
         end
      end
      
      -- Create baseline temporary file for the buffer (this part seems related to diff calculation, keep as is)
      local current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      local temp_file_path = string.format("/tmp/nudge_two_hats_buffer_%d.txt", buf)
      
      -- Ensure m_state.temp_files is initialized
      m_state.temp_files = m_state.temp_files or {}

      -- Remove existing file if it exists, to ensure a fresh baseline
      if vim.fn.filereadable(temp_file_path) == 1 then
        os.remove(temp_file_path)
      end

      local temp_file = io.open(temp_file_path, "w")
      if temp_file then
        temp_file:write(current_content)
        temp_file:close()
        os.execute("chmod 644 " .. temp_file_path)
        m_state.temp_files[buf] = temp_file_path
        if m_config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: Created baseline temp file for buffer %d at %s", buf, temp_file_path))
        end
      else
        if m_config.debug_mode then
          print(string.format("[Nudge Two Hats Debug] BufEnter: Failed to create baseline temp file for buffer %d at %s", buf, temp_file_path))
        end
      end

      -- Start notification timer as well
      if not m_plugin_functions or not m_plugin_functions.start_notification_timer then
        if m_config.debug_mode then
          print("[Nudge Two Hats Debug] ERROR in buf_enter_callback: m_plugin_functions or m_plugin_functions.start_notification_timer is nil. Buffer: " .. buf)
        end
      else
        m_plugin_functions.start_notification_timer(buf, "BufEnter")
        if m_config.debug_mode then
            print(string.format("[Nudge Two Hats Debug] BufEnter: Notification timer started for buffer %d.", buf))
        end
      end
    end
  end
  if m_config and m_config.debug_mode then
    local current_buf_id = vim.api.nvim_get_current_buf()
    print(string.format("[Nudge Two Hats Debug BufEnter] M.buf_enter_callback: END. Execution #%d for buf %d.", buf_enter_execution_count, current_buf_id))
  end
end

-- 自動コマンドを設定する関数
function M.setup(config_param, state_param, plugin_functions_param)
  m_config = config_param
  m_state = state_param
  m_plugin_functions = plugin_functions_param

  local group = vim.api.nvim_create_augroup("nudge-two-hats-autocmd", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    pattern = "*",
    callback = function()
      -- M.clear_tempfiles uses original_config_module or m_config for debug_mode
      M.clear_tempfiles() 
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    pattern = "*",
    callback = function()
      M.buf_leave_callback()
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = function()
      M.buf_enter_callback()
    end,
  })
end

return M
