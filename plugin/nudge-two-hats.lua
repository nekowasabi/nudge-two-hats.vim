if vim.g.loaded_nudge_two_hats then
  return
end
vim.g.loaded_nudge_two_hats = true

-- The plugin is a no-op until the user calls require("nudge-two-hats").setup().
-- No default setup is performed here, because `message` must be injected by the user.
