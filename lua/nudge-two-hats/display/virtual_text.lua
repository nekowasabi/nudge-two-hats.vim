local M = {}

local config = require("nudge-two-hats.config")
local state = require("nudge-two-hats.state")

local NAMESPACE_NAME = "nudge-two-hats-virtual-text"
local HIGHLIGHT = "NudgeTwoHatsVirtualText"

local function ensure_namespace()
  if not state.namespace then
    state.namespace = vim.api.nvim_create_namespace(NAMESPACE_NAME)
  end
  return state.namespace
end

function M.setup_highlight()
  local cfg = config.get().virtual_text
  if not cfg then
    return
  end
  vim.api.nvim_set_hl(0, HIGHLIGHT, {
    fg = cfg.text_color,
    bg = cfg.background_color,
  })
end

--- Clear any nudge virtual text from the given buffer.
function M.clear(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local ns = ensure_namespace()
  local entry = state.buffers[buf]
  if entry and entry.extmark then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, entry.extmark)
    entry.extmark = nil
  else
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  end
end

--- Show `message` as single-line virtual text near the cursor of `buf`.
--- @param buf integer
--- @param message string
function M.show(buf, message)
  if type(message) ~= "string" or message == "" then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local cfg = config.get().virtual_text
  local ns = ensure_namespace()
  local text = message:gsub("[\r\n]+", " ")

  M.clear(buf)

  local row = 0
  if buf == vim.api.nvim_get_current_buf() then
    local ok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
    if ok and pos then
      row = pos[1] - 1
    end
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  if row >= line_count then
    row = math.max(0, line_count - 1)
  end

  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
    virt_text = { { text, HIGHLIGHT } },
    virt_text_pos = cfg.position or "right_align",
    hl_mode = "combine",
  })
  if not ok then
    return
  end
  state.for_buffer(buf).extmark = extmark_id
end

return M
