local M = {}

--- Reset every module owned by this plugin so each spec starts clean.
function M.reset_modules()
  local to_clear = {}
  for name, _ in pairs(package.loaded) do
    if name == "nudge-two-hats" or name:find("^nudge%-two%-hats%.") then
      table.insert(to_clear, name)
    end
  end
  for _, name in ipairs(to_clear) do
    package.loaded[name] = nil
  end
end

--- Create a scratch buffer and return its number.
function M.scratch_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
  })
  vim.api.nvim_set_current_buf(buf)
  return buf
end

return M
