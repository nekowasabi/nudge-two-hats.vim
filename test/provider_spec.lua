local helpers = require("test.helpers")

describe("nudge-two-hats.provider", function()
  local config, provider

  before_each(function()
    helpers.reset_modules()
    config = require("nudge-two-hats.config")
    provider = require("nudge-two-hats.provider")
    config.merge({})
  end)

  describe("build_context", function()
    it("includes buffer, filetype, channel and cursor", function()
      local buf = helpers.scratch_buffer()
      vim.api.nvim_buf_set_option(buf, "filetype", "lua")
      vim.api.nvim_win_set_cursor(0, { 2, 3 })

      local ctx = provider.build_context(buf, "notification")
      assert.equals(buf, ctx.buf)
      assert.equals("lua", ctx.filetype)
      assert.equals("notification", ctx.channel)
      assert.equals(2, ctx.cursor.line)
      assert.equals(3, ctx.cursor.col)
    end)
  end)

  describe("resolve", function()
    it("returns nil when no message is configured", function()
      local ctx = { buf = 0, channel = "notification" }
      assert.is_nil(provider.resolve("notification", ctx))
    end)

    it("invokes a Lua function provider", function()
      config.merge({
        notification = {
          message = function(ctx)
            return "hello " .. ctx.channel
          end,
        },
      })
      local result = provider.resolve("notification", { channel = "notification" })
      assert.equals("hello notification", result)
    end)

    it("treats an unknown string as a literal message", function()
      config.merge({
        virtual_text = { message = "literal hint" },
      })
      local result = provider.resolve("virtual_text", {})
      assert.equals("literal hint", result)
    end)

    it("invokes a Vim script function when the name exists", function()
      vim.cmd([[
        function! NudgeTwoHatsTestProvider(ctx) abort
          return 'vim:' . a:ctx.channel
        endfunction
      ]])
      config.merge({
        notification = { message = "NudgeTwoHatsTestProvider" },
      })
      local result = provider.resolve("notification", { channel = "notification" })
      assert.equals("vim:notification", result)
      vim.cmd("delfunction NudgeTwoHatsTestProvider")
    end)

    it("returns nil when the provider returns an empty string", function()
      config.merge({
        notification = { message = function() return "" end },
      })
      assert.is_nil(provider.resolve("notification", {}))
    end)

    it("swallows provider errors and returns nil", function()
      config.merge({
        notification = { message = function() error("boom") end },
      })
      assert.is_nil(provider.resolve("notification", {}))
    end)
  end)
end)
