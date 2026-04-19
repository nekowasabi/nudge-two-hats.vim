local helpers = require("test.helpers")

describe("nudge-two-hats.display.virtual_text", function()
  local state, virtual_text, config

  before_each(function()
    helpers.reset_modules()
    config = require("nudge-two-hats.config")
    config.merge({})
    state = require("nudge-two-hats.state")
    virtual_text = require("nudge-two-hats.display.virtual_text")
    virtual_text.setup_highlight()
  end)

  local function count_extmarks(buf)
    if not state.namespace then
      return 0
    end
    local marks = vim.api.nvim_buf_get_extmarks(buf, state.namespace, 0, -1, {})
    return #marks
  end

  it("displays a virtual text extmark for the given buffer", function()
    local buf = helpers.scratch_buffer()
    virtual_text.show(buf, "hello")
    assert.equals(1, count_extmarks(buf))
    assert.is_number(state.for_buffer(buf).extmark)
  end)

  it("replaces the previous extmark when show is called twice", function()
    local buf = helpers.scratch_buffer()
    virtual_text.show(buf, "first")
    virtual_text.show(buf, "second")
    assert.equals(1, count_extmarks(buf))
  end)

  it("clears the extmark", function()
    local buf = helpers.scratch_buffer()
    virtual_text.show(buf, "bye")
    virtual_text.clear(buf)
    assert.equals(0, count_extmarks(buf))
    assert.is_nil(state.for_buffer(buf).extmark)
  end)

  it("strips newlines from the displayed text", function()
    local buf = helpers.scratch_buffer()
    virtual_text.show(buf, "a\nb\rc")
    local marks = vim.api.nvim_buf_get_extmarks(
      buf, state.namespace, 0, -1, { details = true }
    )
    assert.equals(1, #marks)
    local chunks = marks[1][4].virt_text
    assert.equals("a b c", chunks[1][1])
  end)

  it("ignores empty or non-string messages", function()
    local buf = helpers.scratch_buffer()
    virtual_text.show(buf, "")
    virtual_text.show(buf, nil)
    assert.equals(0, count_extmarks(buf))
  end)
end)
