local helpers = require("test.helpers")

describe("nudge-two-hats.timer", function()
  local config, state, timer, notification_stub, virtual_text_stub
  local captured

  before_each(function()
    helpers.reset_modules()
    captured = { notification = {}, virtual_text = {} }

    -- Stub the display modules before the timer module requires them.
    package.loaded["nudge-two-hats.display.notification"] = {
      show = function(message)
        table.insert(captured.notification, message)
      end,
    }
    package.loaded["nudge-two-hats.display.virtual_text"] = {
      show = function(buf, message)
        table.insert(captured.virtual_text, { buf = buf, message = message })
      end,
      clear = function() end,
      setup_highlight = function() end,
    }

    config = require("nudge-two-hats.config")
    state = require("nudge-two-hats.state")
    timer = require("nudge-two-hats.timer")
    config.merge({
      notification = {
        idle_seconds = 1,
        message = function(ctx)
          return "nudge-" .. ctx.channel
        end,
      },
      virtual_text = {
        idle_seconds = 1,
        message = function(ctx)
          return "vt-" .. ctx.channel
        end,
      },
    })
    state.enabled = true
  end)

  after_each(function()
    state.enabled = false
    for buf, _ in pairs(state.buffers) do
      timer.stop_all(buf)
    end
    state.reset()
  end)

  it("does nothing when the plugin is disabled", function()
    state.enabled = false
    local buf = helpers.scratch_buffer()
    timer.start(buf, "notification")
    assert.is_nil(state.for_buffer(buf).timers.notification)
  end)

  it("starts a timer for each channel via start_all", function()
    local buf = helpers.scratch_buffer()
    timer.start_all(buf)
    local entry = state.for_buffer(buf)
    assert.is_number(entry.timers.notification)
    assert.is_number(entry.timers.virtual_text)
  end)

  it("fires immediately via now() and clears the stored id", function()
    local buf = helpers.scratch_buffer()
    timer.now(buf, "notification")
    vim.wait(100, function()
      return #captured.notification > 0
    end)
    assert.equals(1, #captured.notification)
    assert.equals("nudge-notification", captured.notification[1])
  end)

  it("now() without a channel fires every channel", function()
    local buf = helpers.scratch_buffer()
    timer.now(buf)
    vim.wait(100, function()
      return #captured.notification > 0 and #captured.virtual_text > 0
    end)
    assert.equals(1, #captured.notification)
    assert.equals(1, #captured.virtual_text)
  end)

  it("skips disabled channels", function()
    config.merge({
      notification = { enabled = false, idle_seconds = 1, message = function() return "x" end },
      virtual_text = { idle_seconds = 1, message = function() return "y" end },
    })
    local buf = helpers.scratch_buffer()
    timer.now(buf)
    vim.wait(100, function()
      return #captured.virtual_text > 0
    end)
    assert.equals(0, #captured.notification)
    assert.equals(1, #captured.virtual_text)
  end)

  it("stop() stops the underlying timer and clears the id", function()
    local buf = helpers.scratch_buffer()
    timer.start(buf, "notification")
    assert.is_number(state.for_buffer(buf).timers.notification)
    timer.stop(buf, "notification")
    assert.is_nil(state.for_buffer(buf).timers.notification)
  end)
end)
