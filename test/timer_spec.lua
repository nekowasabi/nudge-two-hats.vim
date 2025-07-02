-- Unit test for timer functionality
local assert = require('luassert')

describe('nudge-two-hats timer', function()
  -- Test setup
  local timer
  local state = {
    enabled = true, -- Set plugin as enabled for tests
    buf_content = {},
    buf_content_by_filetype = {},
    buf_filetypes = {},
    timers = {
      notification = {},
      virtual_text = {}
    },
    virtual_text = {
      namespace = vim.api.nvim_create_namespace('test-namespace'),
      extmarks = {},
      last_advice = {},
      last_cursor_move = {}
    }
  }
  
  local mock_callback_called = false
  local stored_timer_id = 1001
  
  before_each(function()
    -- Reset state for tests
    mock_callback_called = false
    state.timers.notification = {}
    state.timers.virtual_text = {}
    
    -- Load the timer module
    timer = require('nudge-two-hats.timer')
    
    -- Create a test buffer
    state.test_buf = vim.api.nvim_create_buf(false, true)
    
    -- Store original functions
    state.original_timer_start = vim.fn.timer_start
    state.original_timer_stop = vim.fn.timer_stop
    state.original_timer_info = vim.fn.timer_info
    state.original_nvim_get_current_buf = vim.api.nvim_get_current_buf
    state.original_nvim_buf_get_lines = vim.api.nvim_buf_get_lines
    state.original_nvim_buf_get_option = vim.api.nvim_buf_get_option
    
    -- Mock functions
    vim.fn.timer_start = function(ms, callback)
      -- Store the callback for testing
      if type(callback) == "function" then
        state.stored_callback = callback
      end
      return stored_timer_id
    end
    
    vim.fn.timer_stop = function(timer_id)
      return true
    end
    
    vim.fn.timer_info = function(timer_id)
      return { { id = timer_id, timeout = 1000, callback = function() end } }
    end
    
    vim.api.nvim_get_current_buf = function()
      return state.test_buf
    end
    
    vim.api.nvim_buf_get_lines = function(buf, start, end_line, strict)
      return { "test line 1", "test line 2" }
    end
    
    vim.api.nvim_buf_get_option = function(buf, option)
      if option == "filetype" then
        return "lua"
      end
      return ""
    end
    
    -- Mock the vim.cmd function
    state.original_vim_cmd = vim.cmd
    vim.cmd = function(cmd)
      -- Do nothing in tests
    end
  end)
  
  after_each(function()
    -- Restore original functions
    vim.fn.timer_start = state.original_timer_start
    vim.fn.timer_stop = state.original_timer_stop
    vim.fn.timer_info = state.original_timer_info
    vim.api.nvim_get_current_buf = state.original_nvim_get_current_buf
    vim.api.nvim_buf_get_lines = state.original_nvim_buf_get_lines
    vim.api.nvim_buf_get_option = state.original_nvim_buf_get_option
    vim.cmd = state.original_vim_cmd
    
    -- Clean up test buffer
    pcall(vim.api.nvim_buf_delete, state.test_buf, {force = true})
  end)
  
  it('通知タイマーが正しく停止すること', function()
    -- Setup: first set a notification timer ID in state
    state.timers.notification[state.test_buf] = stored_timer_id
    
    -- Call stop_notification_timer
    local stopped_timer_id = timer.stop_notification_timer(state.test_buf, state)
    
    -- Verify the timer was stopped and timer ID was returned
    assert.equals(stored_timer_id, stopped_timer_id)
    assert.is_nil(state.timers.notification[state.test_buf])
  end)
  
  it('仮想テキストタイマーが正しく停止すること', function()
    -- Setup: first set a virtual text timer ID in state
    state.timers.virtual_text[state.test_buf] = stored_timer_id
    
    -- Call stop_virtual_text_timer
    local stopped_timer_id = timer.stop_virtual_text_timer(state.test_buf, state)
    
    -- Verify the timer was stopped and timer ID was returned
    assert.equals(stored_timer_id, stopped_timer_id)
    assert.is_nil(state.timers.virtual_text[state.test_buf])
  end)
  
  it('通知タイマーが正しく開始すること', function()
    -- Define a mock callback for stop_notification_timer
    local stop_notification_timer_func = function(buf)
      mock_callback_called = true
      return nil
    end
    
    -- Call start_notification_timer
    local timer_id = timer.start_notification_timer(state.test_buf, "test_event", state, stop_notification_timer_func)
    
    -- Verify the timer was started
    assert.equals(stored_timer_id, timer_id)
    assert.equals(stored_timer_id, state.timers.notification[state.test_buf])
    assert.is_true(mock_callback_called)
  end)
  
  it('仮想テキストタイマーが正しく開始すること', function()
    -- Mock the last_cursor_move for state
    state.virtual_text.last_cursor_move[state.test_buf] = os.time()
    
    -- Define a mock display_virtual_text function
    local display_virtual_text_func = function(buf, advice)
      mock_callback_called = true
    end
    
    -- Call start_virtual_text_timer
    local timer_id = timer.start_virtual_text_timer(state.test_buf, "test_event", state, display_virtual_text_func)
    
    -- Verify the timer was started
    assert.equals(stored_timer_id, timer_id)
    assert.equals(stored_timer_id, state.timers.virtual_text[state.test_buf])
  end)
  
  it('両方のタイマーを停止する関数が正しく動作すること', function()
    -- Setup: set timer IDs in state
    state.timers.notification[state.test_buf] = stored_timer_id
    state.timers.virtual_text[state.test_buf] = stored_timer_id + 1
    
    -- Define mock callbacks for stop functions
    local stop_notification_called = false
    local stop_notification_timer_func = function(buf)
      stop_notification_called = true
      return stored_timer_id
    end
    
    local stop_virtual_text_called = false
    local stop_virtual_text_timer_func = function(buf)
      stop_virtual_text_called = true
      return stored_timer_id + 1
    end
    
    -- Call stop_timer
    local stopped_timer_id = timer.stop_timer(state.test_buf, state, stop_notification_timer_func, stop_virtual_text_timer_func)
    
    -- Verify both stop functions were called and timer IDs returned correctly
    assert.is_true(stop_notification_called)
    assert.is_true(stop_virtual_text_called)
    assert.equals(stored_timer_id, stopped_timer_id)
  end)
  
  it('プラグインが無効の場合はタイマーが開始されないこと', function()
    -- Disable the plugin
    state.enabled = false
    
    -- Define a mock callback for stop_notification_timer
    local stop_notification_timer_func = function(buf)
      mock_callback_called = true
      return nil
    end
    
    -- Call start_notification_timer
    local timer_id = timer.start_notification_timer(state.test_buf, "test_event", state, stop_notification_timer_func)
    
    -- Verify the timer was not started
    assert.is_nil(timer_id)
    assert.is_nil(state.timers.notification[state.test_buf])
    
    -- Similar test for virtual text timer
    local display_virtual_text_func = function(buf, advice)
      mock_callback_called = true
    end
    
    local vt_timer_id = timer.start_virtual_text_timer(state.test_buf, "test_event", state, display_virtual_text_func)
    
    -- Verify virtual text timer was not started either
    assert.is_nil(vt_timer_id)
    assert.is_nil(state.timers.virtual_text[state.test_buf])
    
    -- Re-enable the plugin for other tests
    state.enabled = true
  end)
  
  it('should pause notification timer on cursor idle', function()
    -- Mock config with cursor idle threshold
    local config = {
      debug_mode = false,
      notify_interval_seconds = 5,
      cursor_idle_threshold_seconds = 30
    }
    timer.update_config(config)
    
    -- Set up last cursor move time to simulate idle
    state.last_cursor_move_time = {
      [state.test_buf] = os.time() - 31 -- 31 seconds ago
    }
    
    -- Start notification timer
    local stop_func = function(buf)
      timer.stop_notification_timer(buf, state)
    end
    
    timer.start_notification_timer(state.test_buf, "test_event", state, stop_func)
    
    -- Verify timer was started
    assert.is_not_nil(state.timers.notification[state.test_buf])
    
    -- Simulate timer callback execution (which should detect idle and pause)
    -- Since we can't easily trigger the actual timer callback in tests,
    -- we'll test the pause function directly
    timer.pause_notification_timer(state.test_buf, state)
    
    -- Verify timer was paused
    assert.is_nil(state.timers.notification[state.test_buf])
    assert.is_not_nil(state.timers.paused_notification)
    assert.is_not_nil(state.timers.paused_notification[state.test_buf])
  end)
  
  it('should resume notification timer on cursor movement', function()
    -- Mock config
    local config = {
      debug_mode = false,
      notify_interval_seconds = 5,
      cursor_idle_threshold_seconds = 30
    }
    timer.update_config(config)
    
    -- Set up paused timer state
    state.timers.paused_notification = {
      [state.test_buf] = 1234 -- Mock timer ID
    }
    
    -- Resume timer
    local stop_func = function(buf)
      timer.stop_notification_timer(buf, state)
    end
    
    timer.resume_notification_timer(state.test_buf, state, stop_func)
    
    -- Verify timer was resumed
    assert.is_nil(state.timers.paused_notification[state.test_buf])
    assert.is_not_nil(state.timers.notification[state.test_buf])
    assert.is_not_nil(state.last_cursor_move_time[state.test_buf])
  end)
  
  it('should pause virtual text timer on cursor idle', function()
    -- Mock config
    local config = {
      debug_mode = false,
      virtual_text_interval_seconds = 10,
      cursor_idle_threshold_seconds = 30
    }
    timer.update_config(config)
    
    -- Set up last cursor move time to simulate idle
    state.last_cursor_move_time = {
      [state.test_buf] = os.time() - 31 -- 31 seconds ago
    }
    
    -- Start virtual text timer
    local display_func = function(buf, advice)
      -- Mock display function
    end
    
    timer.start_virtual_text_timer(state.test_buf, "test_event", state, display_func)
    
    -- Verify timer was started
    assert.is_not_nil(state.timers.virtual_text[state.test_buf])
    
    -- Pause timer
    timer.pause_virtual_text_timer(state.test_buf, state)
    
    -- Verify timer was paused
    assert.is_nil(state.timers.virtual_text[state.test_buf])
    assert.is_not_nil(state.timers.paused_virtual_text)
    assert.is_not_nil(state.timers.paused_virtual_text[state.test_buf])
  end)
  
  it('should check cursor idle correctly', function()
    -- Mock config
    local config = {
      cursor_idle_threshold_seconds = 30
    }
    timer.update_config(config)
    
    -- Test when cursor has been idle for more than threshold
    state.last_cursor_move_time = {
      [state.test_buf] = os.time() - 31 -- 31 seconds ago
    }
    
    local is_idle = timer.check_cursor_idle(state.test_buf, state)
    assert.is_true(is_idle)
    
    -- Test when cursor has moved recently
    state.last_cursor_move_time[state.test_buf] = os.time() - 10 -- 10 seconds ago
    
    is_idle = timer.check_cursor_idle(state.test_buf, state)
    assert.is_false(is_idle)
    
    -- Test when no cursor move time is recorded
    state.last_cursor_move_time = nil
    
    is_idle = timer.check_cursor_idle(state.test_buf, state)
    assert.is_false(is_idle)
  end)
  
  -- Add more timer tests as needed
end)
