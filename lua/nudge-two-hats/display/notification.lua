local M = {}

local config = require("nudge-two-hats.config")

--- Show a notification message via vim.notify.
--- @param message string
function M.show(message)
  if type(message) ~= "string" or message == "" then
    return
  end
  local cfg = config.get().notification
  vim.notify(message, vim.log.levels.INFO, {
    title = cfg.title,
    icon = cfg.icon,
  })
end

return M
