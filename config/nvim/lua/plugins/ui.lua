-- UI configuration.
--
-- There is exactly one colourscheme: `atlas` (colors/atlas.lua), which reads
-- whichever theme atlas-theme has active. The plugin colourschemes that used to
-- live here (catppuccin, nord, tokyonight, kanagawa, gruvbox, rose-pine,
-- lackluster) are gone on purpose -- themes/ already carries nord, tokyo-night,
-- kanagawa, gruvbox and everforest as palettes, so shipping the plugins too
-- meant two sources of truth for the same colours and an editor that could
-- disagree with the bar it sits under.
--
--   switch themes:  atlas-theme set <name>     (or Super+Alt+T)
--   list them:      atlas-theme list
--
-- Both recolour a running nvim live; no restart, no :colorscheme.

return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "atlas",
    },
  },

  -- Neo-tree: disable git-status name coloring
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      default_component_configs = {
        git_status = {
          symbols = {
            modified = "",
          },
        },
        name = {
          highlight_opened_files = true,
        },
      },
      renderers = {
        file = {
          { "indent" },
          { "icon" },
          { "name", use_git_status_colors = false },
          { "git_status", highlight = "NeoTreeDimText" },
        },
        directory = {
          { "indent" },
          { "icon" },
          { "name", use_git_status_colors = false },
          { "git_status", highlight = "NeoTreeDimText" },
        },
      },
    },
  },

  -- Diffview: side-by-side diffs and merge conflict resolution
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      { "<leader>gdo", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
      { "<leader>gdc", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
      { "<leader>gdh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History (current)" },
      { "<leader>gdH", "<cmd>DiffviewFileHistory<cr>", desc = "File History (all)" },
    },
  },
}
