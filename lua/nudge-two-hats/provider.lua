local M = {}

local config = require("nudge-two-hats.config")

local function debug_log(msg)
  if config.get().debug then
    vim.schedule(function()
      vim.api.nvim_echo({ { "[nudge-two-hats] " .. msg, "Comment" } }, false, {})
    end)
  end
end

--- Build a provider context for a given buffer and channel.
--- @param buf integer buffer number
--- @param channel "notification"|"virtual_text"
--- @return table ctx
function M.build_context(buf, channel)
  local filetype = ""
  if vim.api.nvim_buf_is_valid(buf) then
    filetype = vim.api.nvim_buf_get_option(buf, "filetype") or ""
  end

  local cursor = { line = 1, col = 0 }
  local current_buf = vim.api.nvim_get_current_buf()
  if buf == current_buf then
    local ok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
    if ok and pos then
      cursor = { line = pos[1], col = pos[2] }
    end
  end

  return {
    buf = buf,
    filetype = filetype,
    channel = channel,
    cursor = cursor,
  }
end

--- Resolve the configured message provider for the given channel, then
--- invoke it with the context. Returns `string | nil`.
--- Accepted shapes:
---   * function(ctx) -> string|nil
---   * string (Vim script function name), called as vim.fn[name](ctx)
---   * string literal (fallback: only when not a function name)
--- @param channel "notification"|"virtual_text"
--- @param ctx table
--- @return string|nil message
function M.resolve(channel, ctx)
  local channel_cfg = config.get()[channel]
  if not channel_cfg then
    return nil
  end

  local source = channel_cfg.message
  if source == nil then
    debug_log(channel .. ": message is not configured")
    return nil
  end

  if type(source) == "function" then
    local ok, result = pcall(source, ctx)
    if not ok then
      debug_log(channel .. ": Lua provider raised: " .. tostring(result))
      return nil
    end
    return M._normalize(result)
  end

  if type(source) == "string" then
    -- Prefer Vim script function if one is defined with the given name.
    if vim.fn.exists("*" .. source) == 1 then
      local ok, result = pcall(vim.fn[source], ctx)
      if not ok then
        debug_log(channel .. ": Vim provider '" .. source .. "' raised: " .. tostring(result))
        return nil
      end
      return M._normalize(result)
    end
    -- Not a function name: treat as literal string message.
    return M._normalize(source)
  end

  debug_log(channel .. ": unsupported message type: " .. type(source))
  return nil
end

function M._normalize(value)
  if value == nil then
    return nil
  end
  if type(value) ~= "string" then
    value = tostring(value)
  end
  if value == "" then
    return nil
  end
  return value
end

return M
