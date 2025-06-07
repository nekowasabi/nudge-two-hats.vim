if vim.g.loaded_nudge_two_hats then
  return
end
vim.g.loaded_nudge_two_hats = true

-- Only setup if the module hasn't been explicitly configured by user
if not vim.g.nudge_two_hats_configured then
  require("nudge-two-hats").setup()
end
