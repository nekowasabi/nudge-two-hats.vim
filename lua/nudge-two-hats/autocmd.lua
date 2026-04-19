local M = {}

local state = require("nudge-two-hats.state")
local timer = require("nudge-two-hats.timer")
local virtual_text = require("nudge-two-hats.display.virtual_text")

local GLOBAL_GROUP = "nudge-two-hats"

local function buffer_group_name(buf)
  return "nudge-two-hats-buf-" .. buf
end

--- Cheap helper: only clears virtual text if we actually have one, so the
--- CursorMoved hot path does not touch the extmark API on every keystroke.
local function clear_if_visible(buf)
  local entry = state.buffers[buf]
  if entry and entry.extmark then
    virtual_text.clear(buf)
  end
end

--- Install per-buffer autocmds.
--- * `CursorMoved` (normal/visual) restarts the idle timer and removes any
---   currently displayed virtual text.
--- * Insert mode is treated as "always active": timers are paused on
---   `InsertEnter` and restarted on `InsertLeave`, so typing does not rebuild
---   the timers on every keystroke.
function M.register_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local entry = state.for_buffer(buf)
  if entry.registered then
    return
  end
  entry.registered = true

  local group = vim.api.nvim_create_augroup(buffer_group_name(buf), { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      clear_if_visible(buf)
      timer.start_all(buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      clear_if_visible(buf)
      timer.stop_all(buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
      if not state.enabled then
        return
      end
      timer.start_all(buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.unregister_buffer(buf)
    end,
  })
end

--- Tear down per-buffer autocmds and timers for `buf`.
function M.unregister_buffer(buf)
  timer.stop_all(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    virtual_text.clear(buf)
  end
  pcall(vim.api.nvim_del_augroup_by_name, buffer_group_name(buf))
  state.forget(buf)
end

--- Install the global autocmds (once per Neovim session).
function M.setup_global()
  local group = vim.api.nvim_create_augroup(GLOBAL_GROUP, { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = function(args)
      if not state.enabled then
        return
      end
      local buf = args.buf
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if vim.api.nvim_buf_get_option(buf, "buftype") ~= "" then
        return
      end
      M.register_buffer(buf)
      timer.start_all(buf)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    pattern = "*",
    callback = function()
      timer.stop_every()
    end,
  })
end

return M
