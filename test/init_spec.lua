local helpers = require("test.helpers")

describe("nudge-two-hats (init)", function()
  local nudge, state

  before_each(function()
    helpers.reset_modules()
    package.loaded["nudge-two-hats.display.virtual_text"] = {
      setup_highlight = function() end,
      show = function() end,
      clear = function() end,
    }
    package.loaded["nudge-two-hats.display.notification"] = {
      show = function() end,
    }
    nudge = require("nudge-two-hats")
    state = require("nudge-two-hats.state")
  end)

  after_each(function()
    pcall(function() nudge.disable() end)
    state.reset()
    pcall(vim.api.nvim_del_augroup_by_name, "nudge-two-hats")
  end)

  it("enables the plugin when setup is called", function()
    nudge.setup({
      notification = { idle_seconds = 5, message = function() return "n" end },
      virtual_text = { idle_seconds = 5, message = function() return "v" end },
    })
    assert.is_true(state.enabled)
  end)

  it("registers the expected user commands", function()
    nudge.setup({})
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.NudgeTwoHatsEnable)
    assert.is_not_nil(commands.NudgeTwoHatsDisable)
    assert.is_not_nil(commands.NudgeTwoHatsToggle)
    assert.is_not_nil(commands.NudgeTwoHatsNow)
    assert.is_not_nil(commands.NudgeTwoHatsDebug)
  end)

  it("toggle flips the enabled flag", function()
    nudge.setup({})
    assert.is_true(state.enabled)
    nudge.toggle()
    assert.is_false(state.enabled)
    nudge.toggle()
    assert.is_true(state.enabled)
  end)

  it("disable clears every buffer registration", function()
    nudge.setup({})
    local buf = helpers.scratch_buffer()
    -- Trigger BufEnter manually by re-registering the current buffer.
    require("nudge-two-hats.autocmd").register_buffer(buf)
    require("nudge-two-hats.timer").start_all(buf)
    assert.is_not_nil(state.buffers[buf])
    nudge.disable()
    assert.is_nil(state.buffers[buf])
    assert.is_false(state.enabled)
  end)
end)
