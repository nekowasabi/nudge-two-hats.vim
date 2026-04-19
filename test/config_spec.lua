local helpers = require("test.helpers")

describe("nudge-two-hats.config", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("exposes the documented defaults", function()
    local config = require("nudge-two-hats.config")
    local defaults = config.defaults
    assert.equals(false, defaults.debug)
    assert.equals(300, defaults.notification.idle_seconds)
    assert.equals(60, defaults.virtual_text.idle_seconds)
    assert.equals("right_align", defaults.virtual_text.position)
    assert.is_nil(defaults.notification.message)
  end)

  it("merges user options over the defaults", function()
    local config = require("nudge-two-hats.config")
    local merged = config.merge({
      notification = { idle_seconds = 10, title = "hi" },
      virtual_text = { position = "eol" },
    })
    assert.equals(10, merged.notification.idle_seconds)
    assert.equals("hi", merged.notification.title)
    assert.equals("🎩", merged.notification.icon) -- preserved from defaults
    assert.equals("eol", merged.virtual_text.position)
    assert.equals(60, merged.virtual_text.idle_seconds) -- preserved
  end)

  it("leaves the stored defaults untouched after a merge", function()
    local config = require("nudge-two-hats.config")
    config.merge({ notification = { idle_seconds = 1 } })
    assert.equals(300, config.defaults.notification.idle_seconds)
  end)
end)
