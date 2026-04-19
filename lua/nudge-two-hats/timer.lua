local M = {}

local config = require("nudge-two-hats.config")
local state = require("nudge-two-hats.state")
local provider = require("nudge-two-hats.provider")
local notification = require("nudge-two-hats.display.notification")
local virtual_text = require("nudge-two-hats.display.virtual_text")

local CHANNELS = { "notification", "virtual_text" }

local function channel_cfg(channel)
  return config.get()[channel]
end

local function is_channel_enabled(channel)
  local c = channel_cfg(channel)
  return c and c.enabled ~= false
end

local function idle_ms(channel)
  local seconds = channel_cfg(channel).idle_seconds or 0
  if seconds < 1 then
    seconds = 1
  end
  return seconds * 1000
end

local function show_for_channel(buf, channel, message)
  if channel == "notification" then
    notification.show(message)
  elseif channel == "virtual_text" then
    virtual_text.show(buf, message)
  end
end

local function fire(buf, channel)
  if not state.enabled or not is_channel_enabled(channel) then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    state.forget(buf)
    return
  end

  -- Fire once per idle period. The next tick will be scheduled by
  -- CursorMoved / InsertLeave when the user moves again.
  local entry = state.for_buffer(buf)
  entry.timers[channel] = nil

  -- Defer the actual provider call + display work through vim.schedule so
  -- that if we are invoked from a timer callback we never touch extmark
  -- APIs from an unsafe context, and input processing stays snappy.
  vim.schedule(function()
    if not state.enabled or not is_channel_enabled(channel) then
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      state.forget(buf)
      return
    end
    local ctx = provider.build_context(buf, channel)
    local message = provider.resolve(channel, ctx)
    if message then
      show_for_channel(buf, channel, message)
    end
  end)
end

--- (Re)start the idle timer for `channel` on `buf`. Any previous timer for
--- the same channel/buffer is stopped first.
function M.start(buf, channel)
  if not state.enabled or not is_channel_enabled(channel) then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local entry = state.for_buffer(buf)
  local previous = entry.timers[channel]
  if previous then
    pcall(vim.fn.timer_stop, previous)
    entry.timers[channel] = nil
  end

  local id = vim.fn.timer_start(idle_ms(channel), function()
    fire(buf, channel)
  end)
  entry.timers[channel] = id
end

function M.start_all(buf)
  for _, channel in ipairs(CHANNELS) do
    M.start(buf, channel)
  end
end

function M.stop(buf, channel)
  local entry = state.buffers[buf]
  if not entry then
    return
  end
  local id = entry.timers[channel]
  if id then
    pcall(vim.fn.timer_stop, id)
    entry.timers[channel] = nil
  end
end

function M.stop_all(buf)
  for _, channel in ipairs(CHANNELS) do
    M.stop(buf, channel)
  end
end

function M.stop_every()
  for buf, _ in pairs(state.buffers) do
    M.stop_all(buf)
  end
end

--- Fire a nudge immediately for one channel, or for both when nil.
--- Does not affect the running idle timer.
function M.now(buf, channel)
  if channel then
    fire(buf, channel)
  else
    for _, ch in ipairs(CHANNELS) do
      fire(buf, ch)
    end
  end
end

M.CHANNELS = CHANNELS

return M
