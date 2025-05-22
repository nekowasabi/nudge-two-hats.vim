-- Unit test for autocmd functionality
local assert = require('luassert')

describe('nudge-two-hats autocmd', function()
  -- テスト設定
  local autocmd
  local config = {
    debug_mode = false,
    virtual_text = {
      idle_time = 0.1,
      cursor_idle_delay = 0.1
    }
  }
  
  local state = {
    enabled = true,
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
  
  local plugin_functions = {
    start_notification_timer_called = false,
    start_virtual_text_timer_called = false,
    clear_virtual_text_called = false,
    stop_notification_timer_called = false,
    stop_virtual_text_timer_called = false,
    
    start_notification_timer = function(buf, event_name)
      plugin_functions.start_notification_timer_called = true
      plugin_functions.last_buf = buf
      plugin_functions.last_event = event_name
      return 1001 -- dummy timer ID
    end,
    
    clear_virtual_text = function(buf)
      plugin_functions.clear_virtual_text_called = true
      plugin_functions.last_buf = buf
      return true
    end,
    
    start_virtual_text_timer = function(buf, event_name)
      plugin_functions.start_virtual_text_timer_called = true
      plugin_functions.last_buf = buf
      plugin_functions.last_event = event_name
      return 1002 -- dummy timer ID
    end,
    
    stop_notification_timer = function(buf)
      plugin_functions.stop_notification_timer_called = true
      plugin_functions.last_buf = buf
      return 1001 -- dummy timer ID
    end,
    
    stop_virtual_text_timer = function(buf)
      plugin_functions.stop_virtual_text_timer_called = true
      plugin_functions.last_buf = buf
      return 1002 -- dummy timer ID
    end
  }
  
  before_each(function()
    -- 元のVim関数を保存
    _G.original_vim_api = vim.api
    _G.original_vim_fn = vim.fn
    _G.original_vim_cmd = vim.cmd
    _G.original_vim_defer_fn = vim.defer_fn
    _G.original_io_open = io.open
    
    -- タイマーIDカウンター
    local augroup_id_counter = 1
    
    -- APIのモック
    vim.api = {
      nvim_create_augroup = function(name, opts)
        local id = augroup_id_counter
        augroup_id_counter = augroup_id_counter + 1
        return id
      end,
      
      nvim_create_autocmd = function(events, opts)
        -- 自動コマンドの作成をモック
        -- テスト内でコールバックを実行できるようにする
        if type(events) == "table" then
          for _, event in ipairs(events) do
            if opts.callback then
              -- コールバックを保存して後でテストで使用できるようにする
              state.last_callback = opts.callback
              state.last_event = event
              state.last_buffer = opts.buffer
            end
          end
        else
          if opts.callback then
            state.last_callback = opts.callback
            state.last_event = events
            state.last_buffer = opts.buffer
          end
        end
        
        return 1000 -- dummy autocmd ID
      end,
      
      nvim_buf_get_lines = function(buf, start, end_line, strict)
        return { "test line 1", "test line 2" }
      end,
      
      nvim_buf_get_option = function(buf, option)
        if option == "filetype" then
          return "lua"
        end
        return ""
      end,
      
      nvim_buf_is_valid = function(buf)
        return true
      end,
      
      nvim_get_current_buf = function()
        return 1 -- テスト用バッファID
      end,
      
      nvim_create_namespace = _G.original_vim_api.nvim_create_namespace,
      
      nvim_del_augroup_by_id = function(id)
        -- オートグループの削除をモック
        return true
      end
    }
    
    -- vim.fn のモック
    vim.fn = {
      system = function(cmd)
        -- システムコマンドの実行をモック
        return ""
      end
    }
    
    -- vim.defer_fn のモック
    vim.defer_fn = function(callback, timeout)
      -- 即座にコールバックを実行
      callback()
      return 1000 -- dummy timer ID
    end
    
    -- ファイル操作のモック
    io.open = function(file, mode)
      return {
        write = function(self, data) return true end,
        close = function(self) return true end
      }
    end
    
    -- autocmdモジュールを読み込む
    autocmd = require('nudge-two-hats.autocmd')
    autocmd.update_config(config)
    
    -- テスト用バッファの設定
    state.test_buf = 1
    state.buf_filetypes[state.test_buf] = "lua"
  end)
  
  after_each(function()
    -- 元の関数を復元
    vim.api = _G.original_vim_api
    vim.fn = _G.original_vim_fn
    vim.cmd = _G.original_vim_cmd
    vim.defer_fn = _G.original_vim_defer_fn
    io.open = _G.original_io_open
    
    -- テスト状態をリセット
    plugin_functions.start_notification_timer_called = false
    plugin_functions.start_virtual_text_timer_called = false
    plugin_functions.clear_virtual_text_called = false
    plugin_functions.stop_notification_timer_called = false
    plugin_functions.stop_virtual_text_timer_called = false
  end)
  
  it('自動コマンドが正しく作成されること', function()
    -- create_autocmd関数のテスト
    autocmd.create_autocmd(state.test_buf, state, plugin_functions)
    
    -- 自動コマンドが作成されたことを確認
    assert.is_not_nil(state.last_callback)
    assert.is_not_nil(state.last_event)
    assert.equals(state.test_buf, state.last_buffer)
    
    -- バッファの内容がstateに保存されていることを確認
    assert.is_not_nil(state.buf_content[state.test_buf])
    assert.is_not_nil(state.buf_content_by_filetype[state.test_buf]["lua"])
    
    -- 最後のカーソル移動時間が設定されていることを確認
    assert.is_not_nil(state.virtual_text.last_cursor_move[state.test_buf])
  end)
  
  it('コールバック関数が存在すること', function()
    -- buf_leave_callback関数が存在することを確認
    assert.is_function(autocmd.buf_leave_callback)
    
    -- buf_enter_callback関数が存在することを確認
    assert.is_function(autocmd.buf_enter_callback)
    
    -- clear_tempfiles関数が存在することを確認
    assert.is_function(autocmd.clear_tempfiles)
  end)
  
  it('設定結果の検証', function()
    -- カスタムstateを作成してテスト
    local test_state = {
      enabled = true,
      buf_filetypes = {
        [1] = "lua"
      }
    }
    
    -- setup関数が正常に実行されることを確認
    local success, error_msg = pcall(function()
      autocmd.update_config(config)
      autocmd.setup(test_state, plugin_functions)
    end)
    
    -- エラーが発生しないことを確認
    assert.is_true(success, error_msg)
  end)
  
  it('setupが適切な自動コマンドを登録すること', function()
    -- 自動コマンド設定のテスト
    autocmd.update_config(config)
    autocmd.setup(state, plugin_functions)
    
    -- 少なくとも1つの自動コマンドが作成されたことを確認
    assert.is_not_nil(state.last_callback)
    assert.is_not_nil(state.last_event)
  end)
  
  it('autocmdモジュールが必要な全ての関数を公開していること', function()
    -- 必要な関数のリスト
    local required_functions = {
      'create_autocmd',
      'clear_tempfiles',
      'buf_leave_callback',
      'buf_enter_callback',
      'setup',
      'update_config'
    }
    
    -- 全ての必要な関数が公開されていることを確認
    for _, func_name in ipairs(required_functions) do
      assert.is_function(autocmd[func_name], "Function '" .. func_name .. "' should be exported")
    end
  end)
  
  -- 追加のテストケースを必要に応じて追加
end)
