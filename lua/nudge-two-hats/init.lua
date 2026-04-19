local M = {}

local config = require("nudge-two-hats.config")
local state = require("nudge-two-hats.state")
local timer = require("nudge-two-hats.timer")
local autocmd = require("nudge-two-hats.autocmd")
local virtual_text = require("nudge-two-hats.display.virtual_text")

local VALID_CHANNELS = { notification = true, virtual_text = true }

local function current_buffer()
  return vim.api.nvim_get_current_buf()
end

--- Enable the plugin for the current and future buffers.
function M.enable()
  if state.enabled then
    return
  end
  state.enabled = true
  local buf = current_buffer()
  if vim.api.nvim_buf_is_valid(buf) then
    autocmd.register_buffer(buf)
    timer.start_all(buf)
  end
end

--- Disable the plugin and tear down every buffer-level registration.
function M.disable()
  if not state.enabled then
    return
  end
  state.enabled = false
  local buffers = {}
  for buf, _ in pairs(state.buffers) do
    table.insert(buffers, buf)
  end
  for _, buf in ipairs(buffers) do
    autocmd.unregister_buffer(buf)
  end
end

function M.toggle()
  if state.enabled then
    M.disable()
  else
    M.enable()
  end
end

--- Fire a nudge right now on the current buffer.
--- @param channel? "notification"|"virtual_text"
function M.now(channel)
  if channel and not VALID_CHANNELS[channel] then
    vim.notify(
      "nudge-two-hats: unknown channel '" .. tostring(channel) .. "'",
      vim.log.levels.WARN
    )
    return
  end
  timer.now(current_buffer(), channel)
end

local function describe_timer(id)
  if not id then
    return "-"
  end
  local info = vim.fn.timer_info(id)
  if info and info[1] and info[1].time then
    return string.format("id=%d remaining=%dms", id, info[1].time)
  end
  return string.format("id=%d", id)
end

function M.debug()
  local cfg = config.get()
  local lines = {
    "=== Nudge Two Hats ===",
    ("enabled: %s"):format(tostring(state.enabled)),
    ("notification: enabled=%s idle=%ds"):format(
      tostring(cfg.notification.enabled),
      cfg.notification.idle_seconds
    ),
    ("virtual_text:  enabled=%s idle=%ds"):format(
      tostring(cfg.virtual_text.enabled),
      cfg.virtual_text.idle_seconds
    ),
    "--- buffers ---",
  }
  local any = false
  for buf, entry in pairs(state.buffers) do
    any = true
    local name = ""
    if vim.api.nvim_buf_is_valid(buf) then
      name = vim.api.nvim_buf_get_name(buf)
    end
    table.insert(
      lines,
      ("buf=%d name=%q notification=%s virtual_text=%s"):format(
        buf,
        name,
        describe_timer(entry.timers.notification),
        describe_timer(entry.timers.virtual_text)
      )
    )
  end
  if not any then
    table.insert(lines, "(no registered buffers)")
  end
  table.insert(lines, "======================")

  for _, line in ipairs(lines) do
    vim.api.nvim_echo({ { line } }, false, {})
  end
end

local function register_commands()
  vim.api.nvim_create_user_command("NudgeTwoHatsEnable", function()
    M.enable()
  end, { desc = "Enable nudge-two-hats" })

  vim.api.nvim_create_user_command("NudgeTwoHatsDisable", function()
    M.disable()
  end, { desc = "Disable nudge-two-hats" })

  vim.api.nvim_create_user_command("NudgeTwoHatsToggle", function()
    M.toggle()
  end, { desc = "Toggle nudge-two-hats" })

  vim.api.nvim_create_user_command("NudgeTwoHatsNow", function(opts)
    local channel = opts.args ~= "" and opts.args or nil
    M.now(channel)
  end, {
    desc = "Fire nudge immediately ([notification|virtual_text])",
    nargs = "?",
    complete = function()
      return { "notification", "virtual_text" }
    end,
  })

  vim.api.nvim_create_user_command("NudgeTwoHatsDebug", function()
    M.debug()
  end, { desc = "Show nudge-two-hats debug information" })
end

--- Initialize the plugin. Safe to call multiple times; the latest options win.
--- The plugin is automatically enabled after setup.
--- @param opts? table
function M.setup(opts)
  config.merge(opts)
  virtual_text.setup_highlight()
  autocmd.setup_global()
  register_commands()
  M.enable()
end

return M
