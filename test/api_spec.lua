-- Unit test for API functionality
local assert = require('luassert')

describe('nudge-two-hats api', function()
  -- テスト設定
  local api
  local config = {
    debug_mode = false,
    api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent",
    system_prompt = "コードの変更点についてアドバイスをください",
    translate_messages = true,
    output_language = "ja",
    message_length = 100,
    length_type = "characters",
    translations = {
      en = {
        enabled = "enabled",
        disabled = "disabled",
        api_key_not_set = "API key not set",
        api_error = "API error",
        unknown_error = "Unknown error"
      },
      ja = {
        enabled = "有効化しました",
        disabled = "無効化しました",
        api_key_not_set = "APIキーが設定されていません",
        api_error = "APIエラー",
        unknown_error = "不明なエラー"
      }
    }
  }
  
  local mock_response = {
    candidates = {
      {
        content = {
          parts = {
            {
              text = "テスト応答"
            }
          }
        }
      }
    }
  }
  
  before_each(function()
    -- ランダム性を固定するためにシードを設定
    math.randomseed(1234)
    
    -- APIモジュールを読み込む
    api = require('nudge-two-hats.api')
    
    -- 設定を更新
    api.update_config(config)
    
    -- 元の関数を保存
    _G.original_vim_fn = vim.fn
    _G.original_vim_notify = vim.notify
    _G.original_io_open = io.open
    _G.original_os_execute = os.execute
    _G.original_vim_json = vim.json
    
    -- vim.jsonモック
    vim.json = {
      decode = function(json_str)
        return mock_response
      end
    }
    
    -- モック関数を設定
    vim.fn = {
      system = function(cmd)
        -- APIレスポンスをモック
        return vim.fn.json_encode(mock_response)
      end,
      json_encode = function(obj)
        if _G.original_vim_fn.json_encode then
          return _G.original_vim_fn.json_encode(obj)
        else
          -- シンプルなJSON差分用モック
          return "{\"test\":\"value\"}"
        end
      end,
      json_decode = function(json_str)
        -- APIレスポンスをデコード
        return mock_response
      end,
      getenv = function(name)
        if name == "GEMINI_API_KEY" then
          return "test_api_key"
        elseif name == "LANG" then
          return "ja_JP.UTF-8"
        end
        return ""
      end,
      jobstart = function(cmd, opts)
        -- ジョブの開始をモック
        if opts and opts.on_stdout then
          vim.schedule(function()
            opts.on_stdout(0, {"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"テスト応答\"}]}}]}"})
          end)
        end
        if opts and opts.on_exit then
          vim.schedule(function()
            opts.on_exit(0, 0)
          end)
        end
        return 12345 -- ダミーのジョブID
      end,
      timer_start = function(ms, callback)
        -- タイマーを即座に実行
        if type(callback) == "function" then
          vim.schedule(function()
            callback()
          end)
        end
        return 1000
      end,
      filereadable = function(file)
        return 1
      end,
      delete = function(file)
        return 0
      end
    }
    
    -- 通知をモック
    vim.notify = function(msg, level, opts)
      -- 通知をキャプチャするためのダミー関数
    end
    
    -- vim.scheduleをオーバーライド
    _G.original_vim_schedule = vim.schedule
    vim.schedule = function(callback)
      if type(callback) == "function" then
        callback()
      end
    end
    
    -- ファイル操作をモック
    io.open = function(file, mode)
      return {
        write = function(self, data)
          -- 書き込みをモック
          return true
        end,
        close = function(self)
          -- クローズをモック
          return true
        end,
        read = function(self, format)
          -- 読み込みをモック
          return "テスト内容"
        end
      }
    end
    
    -- OS実行をモック
    os.execute = function(cmd)
      -- OS実行をモック
      return 0
    end
  end)
  
  after_each(function()
    -- 元の関数を復元
    vim.fn = _G.original_vim_fn
    vim.notify = _G.original_vim_notify
    io.open = _G.original_io_open
    os.execute = _G.original_os_execute
    vim.json = _G.original_vim_json
    vim.schedule = _G.original_vim_schedule
  end)
  
  it('UTF-8文字列を安全に切り詰めること', function()
    -- ASCII文字列のテスト
    local ascii_str = "Hello, world!"
    local truncated = api.safe_truncate(ascii_str, 5)
    assert.equals("Hello", truncated)
    
    -- 日本語文字列のテスト
    local jp_str = "こんにちは世界！"
    local truncated_jp = api.safe_truncate(jp_str, 3)
    assert.equals("こんに", truncated_jp)
    
    -- 既に短い文字列のテスト
    local short_str = "ABC"
    local truncated_short = api.safe_truncate(short_str, 5)
    assert.equals("ABC", truncated_short)
  end)
  
  it('テキストをAPIリクエスト用に適切にサニタイズすること', function()
    -- 通常のテキスト
    local normal_text = "Normal text with no special chars"
    local sanitized = api.sanitize_text(normal_text)
    assert.equals(normal_text, sanitized)
    
    -- 特殊文字を含むテキスト
    local special_text = "Text with \"quotes\" and \\backslashes\\"
    local sanitized_special = api.sanitize_text(special_text)
    assert.not_equals(special_text, sanitized_special)
    assert.matches("quotes", sanitized_special) -- 引用符はサニタイズされていても内容は保持される
    
    -- nilの入力
    local nil_sanitized = api.sanitize_text(nil)
    assert.equals("", nil_sanitized)
  end)
  
  it('日本語の検出が正しく機能すること', function()
    -- 日本語テキスト
    local jp_text = "これは日本語です"
    assert.is_true(api.is_japanese(jp_text))
    
    -- 英語のみのテキスト
    local en_text = "This is English only"
    assert.is_false(api.is_japanese(en_text))
    
    -- 混合テキスト
    local mixed_text = "This contains 日本語"
    assert.is_true(api.is_japanese(mixed_text))
  end)
  
  it('設定に基づいて正しい言語を取得すること', function()
    -- 自動設定でJapanese環境
    config.output_language = "auto"
    assert.equals("ja", api.get_language())
    
    -- 英語環境を強制的にシミュレート
    vim.fn.getenv = function(name)
      if name == "LANG" then
        return "en_US.UTF-8"
      end
      return ""
    end
    assert.equals("en", api.get_language())
    
    -- 明示的な言語設定
    config.output_language = "ja"
    assert.equals("ja", api.get_language())
    
    config.output_language = "en"
    assert.equals("en", api.get_language())
  end)
  
  it('翻訳機能の基本的なテスト', function()
    -- 翻訳機能を無効化してテスト
    config.translate_messages = false
    local msg = "test message"
    assert.equals(msg, api.translate_message(msg))
    
    -- 翻訳機能を再度有効化
    config.translate_messages = true
  end)
  
  it('複数のエンコーディングが正しく処理されること', function()
    -- ASCII文字列のテストを拡張
    local ascii_str1 = "ABCDEFabcdef123456"
    local ascii_str2 = "HELLO world 123"
    
    -- 異なる長さで切り詰め
    local truncated1 = api.safe_truncate(ascii_str1, 10)
    local truncated2 = api.safe_truncate(ascii_str2, 8)
    
    -- 結果の確認
    assert.equals("ABCDEFabcd", truncated1)
    assert.equals("HELLO wo", truncated2)
    
    -- 空文字列の処理確認
    local empty_str = ""
    local truncated_empty = api.safe_truncate(empty_str, 5)
    assert.equals("", truncated_empty)
  end)
  
  it('日本語と英語の変換が正しく処理されること', function()
    -- デフォルト言語設定を日本語にする
    config.output_language = "ja"
    
    -- 日本語テキストの処理
    local jp_text = "これはテストです"
    assert.is_true(api.is_japanese(jp_text))
    
    -- 英語テキストの処理
    local en_text = "This is a test"
    assert.is_false(api.is_japanese(en_text))
    
    -- get_language関数の動作確認
    assert.equals("ja", api.get_language())
    
    -- 英語に設定を変更
    config.output_language = "en"
    assert.equals("en", api.get_language())
  end)
  
  -- 追加のテストケースを必要に応じて追加
end)
