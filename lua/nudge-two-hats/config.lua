local M = {}

--- Default configuration.
---
--- `message` accepts either a Lua function or a Vim script function name (string).
--- It is invoked with one argument: the provider context table
---   ctx = { buf, filetype, channel, cursor = { line, col } }
--- Return `string` to display, or `nil` to skip this nudge.
M.defaults = {
  debug = false,

  notification = {
    enabled = true,
    idle_seconds = 300,
    message = nil,
    title = "Nudge Two Hats",
    icon = "🎩",
  },

  virtual_text = {
    enabled = true,
    idle_seconds = 60,
    message = nil,
    position = "right_align",
    text_color = "#AABBCC",
    background_color = "#112233",
  },
}

M.current = vim.deepcopy(M.defaults)

function M.merge(user_opts)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
  return M.current
end

function M.get()
  return M.current
end

return M
