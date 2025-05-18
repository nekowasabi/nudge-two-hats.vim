-- Unit test for virtual text functionality
local assert = require('luassert')

describe('nudge-two-hats virtual text', function()
  -- Test setup
  local virtual_text
  local state = {
    enabled = true, -- Set plugin as enabled for tests
    stop_timer = function() end, -- Mock stop_timer function
    virtual_text = {
      namespace = vim.api.nvim_create_namespace('test-namespace'),
      extmarks = {},
      last_advice = {}
    }
  }
  
  before_each(function()
    -- Load the virtual_text module
    virtual_text = require('nudge-two-hats.virtual_text')
    
    -- Initialize the module with test state
    virtual_text.init(state)
    
    -- Create a test buffer
    state.test_buf = vim.api.nvim_create_buf(false, true)
    
    -- Mock nvim_win_get_cursor
    state.original_nvim_win_get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function(win)
      return {1, 0} -- Line 1, column 0
    end
    
    -- Setup mock functions
    state.original_nvim_buf_set_extmark = vim.api.nvim_buf_set_extmark
    vim.api.nvim_buf_set_extmark = function(buf, ns, line, col, opts)
      -- Mock implementation that just returns a fake extmark ID
      return 1000
    end
    
    -- Mock other required functions
    state.original_nvim_buf_del_extmark = vim.api.nvim_buf_del_extmark
    vim.api.nvim_buf_del_extmark = function(buf, ns, id)
      -- Mock implementation
      return true
    end
  end)
  
  after_each(function()
    -- Restore original functions
    vim.api.nvim_buf_set_extmark = state.original_nvim_buf_set_extmark
    vim.api.nvim_buf_del_extmark = state.original_nvim_buf_del_extmark
    vim.api.nvim_win_get_cursor = state.original_nvim_win_get_cursor
    
    -- Clean up test buffer
    pcall(vim.api.nvim_buf_delete, state.test_buf, {force = true})
  end)
  
  it('仮想テキストが正しく表示されること', function()
    -- Test advice text
    local test_advice = "Consider using a for loop here"
    
    -- Call the function
    virtual_text.display_virtual_text(state.test_buf, test_advice)
    
    -- Verify that an extmark was created (stored in state)
    assert.is_not_nil(state.virtual_text.extmarks[state.test_buf])
    assert.equals(1000, state.virtual_text.extmarks[state.test_buf]) -- Our mock returns 1000
    assert.equals(test_advice, state.virtual_text.last_advice[state.test_buf])
  end)
  
  it('仮想テキストが正しくクリアされること', function()
    -- Setup: first add some virtual text to establish a state
    state.virtual_text.extmarks[state.test_buf] = 1000
    
    -- Verify the setup worked
    assert.equals(1000, state.virtual_text.extmarks[state.test_buf])
    
    -- Call the clear function
    virtual_text.clear_virtual_text(state.test_buf)
    
    -- Verify the extmark was cleared from state
    assert.is_nil(state.virtual_text.extmarks[state.test_buf])
  end)
  
  it('プラグインが無効の場合は何もしないこと', function()
    -- Disable the plugin
    state.enabled = false
    
    -- Call the function
    virtual_text.display_virtual_text(state.test_buf, "This should not be displayed")
    
    -- Verify no extmark was created
    assert.is_nil(state.virtual_text.extmarks[state.test_buf])
    
    -- Re-enable the plugin for other tests
    state.enabled = true
  end)
  
  -- Add more specific tests as needed
end)