-- User keymaps. LazyVim loads this AFTER its own defaults, so maps here win.

-- <leader>uh — toggle the atlas background between transparent and solid.
-- NOTE: overrides LazyVim's default inlay-hints toggle (also <leader>uh).
--
-- colors/atlas.lua reads `vim.g.atlas_transparent` (default true) at load, so
-- flipping the flag and re-sourcing swaps the background. Transparent is the
-- default because mango blurs behind the window, same as ghostty.
vim.keymap.set("n", "<leader>uh", function()
  if (vim.g.colors_name or "") ~= "atlas" then
    vim.notify("Transparency toggle only applies to the atlas theme", vim.log.levels.WARN)
    return
  end
  local cur = vim.g.atlas_transparent
  if cur == nil then
    cur = true
  end
  vim.g.atlas_transparent = not cur
  vim.cmd("colorscheme atlas")
  vim.notify("Atlas background: " .. (vim.g.atlas_transparent and "transparent" or "solid"))
end, { desc = "Toggle atlas transparency" })
