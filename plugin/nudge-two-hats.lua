if vim.g.loaded_nudge_two_hats then
  return
end
vim.g.loaded_nudge_two_hats = true

require("nudge-two-hats").setup()
