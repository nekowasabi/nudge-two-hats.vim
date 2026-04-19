local M = {}

--- Plugin-wide state.
M.enabled = false
M.namespace = nil

--- Per-buffer state. Each entry lazily created.
--- Shape:
---   {
---     timers  = { notification = <id|nil>, virtual_text = <id|nil> },
---     extmark = <id|nil>,
---     registered = <bool>, -- whether per-buffer autocmds are installed
---   }
M.buffers = {}

function M.for_buffer(buf)
  local entry = M.buffers[buf]
  if entry == nil then
    entry = {
      timers = { notification = nil, virtual_text = nil },
      extmark = nil,
      registered = false,
    }
    M.buffers[buf] = entry
  end
  return entry
end

function M.forget(buf)
  M.buffers[buf] = nil
end

function M.reset()
  M.enabled = false
  M.namespace = nil
  M.buffers = {}
end

return M
