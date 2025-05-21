local M = {}

-- デフォルト設定
local config = require("nudge-two-hats.config")

-- APIモジュールの読み込み
local api = require("nudge-two-hats.api")
-- 状態管理用の変数（init.luaから受け取ります）
local state = nil

-- ログファイルを開くヘルパー関数
local function open_log_file()
  if config.debug_mode then
    return io.open("/tmp/nudge_two_hats_virtual_text_debug.log", "a")
  end
  return nil
end

-- 設定を更新する関数
function M.update_config(new_config)
  config = new_config
end

-- 状態を初期化する関数
function M.init(global_state)
  state = global_state
end

-- 仮想テキストをクリアする関数
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

-- 仮想テキストを表示する関数
function M.display_virtual_text(buf, advice)
  -- 仮想テキスト表示関数では切り詰めを行わない
  -- 既にAPIコールで指定した長さのメッセージが生成されている
  local message_length = config.virtual_text_message_length

  if config.debug_mode then
    print(string.format("[Nudge Two Hats Debug] Virtual text advice length: %d, expected: %d", #advice, message_length))
  end

  -- -- virtual_text_message_lengthが小さい場合は差し替えを実行
  -- if config.notify_message_length > config.virtual_text_message_length then
  --   if config.debug_mode then
  --     print(string.format("[Nudge Two Hats Debug] Temporarily swapping notify_message_length %d with virtual_text_message_length %d",
  --                       config.notify_message_length, config.virtual_text_message_length))
  --   end
  --   -- notify_message_length に virtual_text_message_length を設定 (一時的)
  --   config.notify_message_length = config.virtual_text_message_length
  --   temp_swap = true
  -- end
  local log_file = open_log_file()
  if log_file then
    log_file:write("=== display_virtual_text called at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    log_file:write("Buffer: " .. buf .. "\n")
    log_file:write("Plugin enabled: " .. tostring(state.enabled) .. "\n")
    log_file:write("Setting context_for to virtual_text\n")
    log_file:write("Advice length: " .. #advice .. " characters\n")
    log_file:write("Advice: " .. advice .. "\n")
    -- 仮想テキスト用のコンテキストを設定
    state.context_for = "virtual_text"
    if not state.enabled then
      log_file:write("Plugin not enabled, exiting display_virtual_text\n\n")
      log_file:close()
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
  -- 仮想テキスト用のコンテキストを設定
  state.context_for = "virtual_text"
  M.clear_virtual_text(buf)
  -- timerモジュールからstop_timer関数を直接呼び出さず、渡された関数を使用
  if state.stop_timer then
    state.stop_timer(buf)
  end
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
    virt_text_pos = "right_align",
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

-- テスト用：仮想テキストを即座に表示するコマンド
function M.test_virtual_text(test_message)
  -- 現在のバッファを取得
  local current_buf = vim.api.nvim_get_current_buf()
  -- テストメッセージを設定（指定がなければデフォルトのメッセージを使用）
  local message = test_message or "⚙️ Virtual text test message - "..os.date("%H:%M:%S")
  -- 仮想テキストを表示
  M.display_virtual_text(current_buf, message)
  if config.debug_mode then
    print("[Nudge Two Hats Debug] Test virtual text command executed")
  end
end

return M
