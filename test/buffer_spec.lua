-- Unit test for buffer functionality
local assert = require('luassert')

describe('nudge-two-hats buffer', function()
  -- Test setup
  local buffer
  local config = {
    debug_mode = false,
    notify_min_interval = 30,
    notify_interval_correction = 1.1,
    virtual_text_min_interval = 30,
    callback = "",
    filetype_prompts = {
      lua = {
        role = "Luaプログラマー",
        direction = "コードの質向上を支援します",
        emotion = "思慮深い",
        tone = "専門的",
        prompt = "Luaコードの改善点を具体的に教えてください",
        hats = {"Luaエキスパート", "メンター"},
        callback = ""
      },
      javascript = "JavaScriptのコードレビューをお願いします",
      python = {
        role = "Pythonエンジニア",
        direction = "Pythonベストプラクティスを提案します",
        emotion = "分析的",
        tone = "教育的",
        prompt = "このPythonコードをどう改善できますか？",
        hats = {"Python達人", "コードレビュアー"},
        callback = ""
      }
    },
    default_cbt = {
      role = "コーディングアシスタント",
      direction = "コード品質向上のための提案を行います",
      emotion = "協力的",
      tone = "友好的",
      hats = {"アドバイザー", "メンター", "コーチ"}
    },
    system_prompt = "デフォルトのプロンプトです"
  }
  
  local state = {
    enabled = true,
    buf_content = {},
    buf_content_by_filetype = {},
    buf_filetypes = {},
    virtual_text = {
      last_advice = {}
    }
  }
  
  before_each(function()
    -- Reset math.random seed for predictable tests
    math.randomseed(1234)
    
    -- Load the buffer module
    buffer = require('nudge-two-hats.buffer')
    
    -- Update config
    buffer.update_config(config)
    
    -- Create a test buffer
    state.test_buf = vim.api.nvim_create_buf(false, true)
    
    -- Store original functions
    state.original_nvim_buf_get_lines = vim.api.nvim_buf_get_lines
    state.original_nvim_buf_get_option = vim.api.nvim_buf_get_option
    state.original_nvim_buf_line_count = vim.api.nvim_buf_line_count
    state.original_nvim_win_get_cursor = vim.api.nvim_win_get_cursor
    state.original_diff = vim.diff
    
    -- Mock functions
    vim.api.nvim_buf_get_lines = function(buf, start, end_line, strict)
      return { "test line 1", "test line 2", "test line 3" }
    end
    
    vim.api.nvim_buf_get_option = function(buf, option)
      if option == "filetype" then
        return "lua"
      end
      return ""
    end
    
    vim.api.nvim_buf_line_count = function(buf)
      return 3
    end
    
    vim.api.nvim_win_get_cursor = function(win)
      return {2, 0} -- Line 2, column 0
    end
    
    vim.diff = function(a, b, opts)
      if a ~= b then
        return "--- a/old\n+++ b/new\n@@ -1,3 +1,3 @@\n-old line 1\n+new line 1\n old line 2\n old line 3\n"
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
    vim.api.nvim_buf_get_lines = state.original_nvim_buf_get_lines
    vim.api.nvim_buf_get_option = state.original_nvim_buf_get_option
    vim.api.nvim_buf_line_count = state.original_nvim_buf_line_count
    vim.api.nvim_win_get_cursor = state.original_nvim_win_get_cursor
    vim.diff = state.original_diff
    vim.cmd = state.original_vim_cmd

    -- Clean up test buffer
    pcall(vim.api.nvim_buf_delete, state.test_buf, {force = true})
  end)

  it('callbackが存在する場合プロンプトに含めること', function()
    config.callback = 'TestCallback'
    vim.fn.exists = function(name)
      if name == '*TestCallback' then
        return 1
      end
      return 0
    end
    vim.fn.TestCallback = function()
      return 'CB'
    end
    buffer.update_config(config)
    state.buf_filetypes[state.test_buf] = 'lua'
    local prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    print('Actual prompt:', prompt)
    assert.matches('CB', prompt)
  end)

  it('ファイルタイプ固有のcallbackが優先されること', function()
    config.callback = ''
    config.filetype_prompts.lua.callback = 'LuaCb'
    vim.fn.exists = function(name)
      if name == '*LuaCb' then
        return 1
      end
      return 0
    end
    vim.fn.LuaCb = function()
      return 'LUA_CB'
    end
    buffer.update_config(config)
    state.buf_filetypes[state.test_buf] = 'lua'
    local prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    assert.matches('LUA_CB', prompt)
  end)

  it('存在しないcallbackは空文字を追加するだけ', function()
    config.callback = 'NoFunc'
    vim.fn.exists = function()
      return 0
    end
    buffer.update_config(config)
    state.buf_filetypes[state.test_buf] = 'javascript'
    local prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    assert.equals('JavaScriptのコードレビューをお願いします', prompt)
  end)
  
  it('バッファの差分を正しく検出すること', function()
    -- Setup: store initial buffer content
    local initial_content = "old content"
    state.buf_content[state.test_buf] = initial_content
    state.buf_content_by_filetype[state.test_buf] = { lua = initial_content }
    
    -- Set mock current content
    vim.api.nvim_buf_get_lines = function(buf, start, end_line, strict)
      return { "new content" }
    end
    
    -- Call get_buf_diff
    local new_content, diff, detected_filetype = buffer.get_buf_diff(state.test_buf, state)
    
    -- Verify diff was detected
    assert.is_not_nil(diff)
    assert.equals("lua", detected_filetype)
    assert.equals("new content", new_content)
  end)
  
  it('初回の通知では特別な差分を生成すること', function()
    -- Setup: empty state to trigger first notification
    state.buf_content = {}
    state.buf_content_by_filetype = {}
    
    -- Call get_buf_diff
    local content, diff, detected_filetype = buffer.get_buf_diff(state.test_buf, state)
    
    -- Verify special first-time diff was created
    assert.is_not_nil(diff)
    assert.is_not_nil(content)
    assert.equals("lua", detected_filetype)
    assert.matches("@@ %-0,0 %+1,%d+ @@", diff) -- Pattern for first-time diff
  end)
  
  it('Luaファイルタイプ用のプロンプトを正しく生成すること', function()
    -- Setup: set buffer filetype to lua
    state.buf_filetypes[state.test_buf] = "lua"
    
    -- Call get_prompt_for_buffer
    local prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    
    -- Verify prompt contains expected content
    assert.matches("Lua", prompt)
    assert.matches("コードの質向上", prompt)
    
    -- Verify hat was selected
    local hat = buffer.get_selected_hat()
    assert.is_not_nil(hat)
    assert.is_true(hat == "Luaエキスパート" or hat == "メンター")
  end)
  
  it('JavaScriptファイルタイプ用の文字列プロンプトを正しく処理すること', function()
    -- Setup: set buffer filetype to javascript
    state.buf_filetypes[state.test_buf] = "javascript"
    
    -- Call get_prompt_for_buffer
    local prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    
    -- Verify prompt is the exact string
    assert.equals("JavaScriptのコードレビューをお願いします", prompt)
    
    -- Verify no hat was selected
    local hat = buffer.get_selected_hat()
    assert.is_nil(hat)
  end)
  
  it('未知のファイルタイプにはデフォルトプロンプトを使用すること', function()
    -- Setup: set buffer filetype to an unknown type
    state.buf_filetypes[state.test_buf] = "unknown_filetype"
    
    -- Call get_prompt_for_buffer
    local prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    
    -- Verify default prompt is used
    assert.equals(config.system_prompt, prompt)
    
    -- Verify no hat was selected
    local hat = buffer.get_selected_hat()
    assert.is_nil(hat)
  end)
  
  it('init.vimで指定した設定が正しく反映されること', function()
    -- Setup: init.vimからのカスタム設定をシミュレート
    local custom_config = {
      system_prompt = "Give advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      filetype_prompts = {
        markdown = {
          prompt = "Give advice about this writing, focusing on clarity and structure.",
          role = "Cognitive behavioral therapy specialist",
          direction = "Guide towards clearer and more structured writing",
          emotion = "Empathetic and understanding",
          tone = "Supportive and encouraging but direct",
        },
        text = {
          purpose = "集中が途切れないように、ナッジによってさりげなく現在の行動を促す",
          hats = {
            "law",
            "chaos",
            "neutral",
            "trickster",
          },
          prompt = "テキスト内容を題材として、アドバイスしてください。前置きなしで、端的にメッセージのみを出力してください。",
          role = "トリックスターであり、常に民衆の意表を突く発言のみを行う",
          direction = "意味深なアドバイスを行う",
          emotion = "Empathetic and understanding",
          tone = "前置きなしで、直接的に",
        },
        lua = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
        python = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      },
      message_length = 100,
      length_type = "characters",
      output_language = "ja",
      translate_messages = true,
      notify_min_interval = 6,
      notify_interval_correction = 1.1,
      virtual_text_min_interval = 6,
      virtual_text = {
        idle_time = 0.1,
        cursor_idle_delay = 0.1,
        text_color = "#000000",
        background_color = "#FFFFFF",
      },
      debug_mode = false,
    }
    
    -- モジュールを再ロードして設定を更新
    buffer.update_config(custom_config)
    
    -- テスト1: カスタム設定がLuaファイルタイプに反映されていることを確認
    state.buf_filetypes[state.test_buf] = "lua"
    local lua_prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    assert.equals("Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.", lua_prompt)
    assert.is_nil(buffer.get_selected_hat())
    
    -- テスト2: text用のカスタム設定（複雑な構造）が正しく反映されていることを確認
    state.buf_filetypes[state.test_buf] = "text"
    local text_prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    
    -- 複雑なオブジェクト型の設定が正しくフォーマットされていることを確認
    assert.matches("トリックスター", text_prompt)
    assert.matches("意味深なアドバイス", text_prompt)
    
    -- ハットが正しく選択されていることを確認
    local hat = buffer.get_selected_hat()
    assert.is_not_nil(hat)
    -- 指定されたハットのいずれかが選択されていることを確認
    assert.is_true(hat == "law" or hat == "chaos" or hat == "neutral" or hat == "trickster")
    
    -- テスト3: システムプロンプトがカスタム設定に更新されていることを確認
    state.buf_filetypes[state.test_buf] = "unknown_filetype"
    local default_prompt = buffer.get_prompt_for_buffer(state.test_buf, state)
    assert.equals(custom_config.system_prompt, default_prompt)
  end)
  
  -- Add more buffer tests as needed
end)
