-- Ricing: dashboard, statusline, tabs, delimiters, animations, and eye candy
return {
  -----------------------------------------------------------------------------
  -- 3a. Snacks Dashboard - Custom ASCII Art + LazyGit Shortcut
  -----------------------------------------------------------------------------
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = [[
░█▀█░▀█▀░█░░░█▀█░█▀▀
░█▀█░░█░░█░░░█▀█░▀▀█
░▀░▀░░▀░░▀▀▀░▀░▀░▀▀▀]],
          keys = {
            { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
            { icon = " ", key = "s", desc = "Restore Session", section = "session" },
            { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
            { icon = " ", key = "G", desc = "LazyGit", action = ":lua Snacks.lazygit()" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          -- Which theme is live, so the dashboard answers the question you ask
          -- it most often after `atlas-theme set`.
          --
          -- This is a snacks.dashboard.Gen -- a function returning a SECTION.
          -- `text` itself must be a string or Text[]; handing it a function
          -- gets you "attempt to index local 'texts' (a function value)" out of
          -- dashboard.lua:372. Being a Gen also means it re-reads the palette
          -- each time the dashboard opens, so it stays right after a switch.
          function()
            local ok, roles = pcall(require, "atlas.roles")
            local name = ok and roles.palette().NAME or "Atlas"
            return {
              padding = 1,
              text = { { "󰏘  " .. name, hl = "SnacksDashboardFooter", align = "center" } },
            }
          end,
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
      -- 3g. Snacks Overrides
      notifier = { style = "fancy" },
      words = { enabled = true },
      scope = { enabled = true },
    },
  },

  -----------------------------------------------------------------------------
  -- 3b. Lualine - Powerline Separators + Custom Sections
  -----------------------------------------------------------------------------
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      -- Statusline colours come from the active atlas palette, so the bar
      -- recolours with the desktop instead of sitting on a LazyVim default.
      opts.options.theme = require("atlas.lualine")()
      opts.options.section_separators = { left = "", right = "" }
      opts.options.component_separators = { left = "", right = "" }
      opts.sections = opts.sections or {}
      opts.sections.lualine_y = { "encoding", "fileformat", "progress", "location" }
      opts.sections.lualine_z = {
        { "filetype", icon_only = false, separator = "", padding = { left = 1, right = 1 } },
      }
    end,
  },

  -----------------------------------------------------------------------------
  -- 3c. Bufferline - Slant Separators + Underline Indicator
  -----------------------------------------------------------------------------
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.separator_style = "slant"
      opts.options.indicator = { style = "underline" }
      opts.options.hover = { enabled = true, delay = 200, reveal = { "close" } }
      -- No integration shim here: colors/atlas.lua sets every BufferLine* group
      -- directly, so the tabs follow the theme with nothing to keep in sync.
    end,
  },

  -----------------------------------------------------------------------------
  -- 3d. Rainbow Delimiters
  -----------------------------------------------------------------------------
  {
    "HiPhish/rainbow-delimiters.nvim",
    event = "BufReadPost",
    config = function()
      local rainbow = require("rainbow-delimiters")
      vim.g.rainbow_delimiters = {
        strategy = {
          -- Return nil for filetypes without a treesitter grammar installed
          -- (Neovim 0.12 returns identity mapping from get_lang instead of nil)
          [""] = function(bufnr)
            local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].ft)
            if not lang or not pcall(vim.treesitter.language.inspect, lang) then
              return nil
            end
            return rainbow.strategy["global"]
          end,
        },
        query = { [""] = "rainbow-delimiters" },
        highlight = {
          "RainbowDelimiterRed",
          "RainbowDelimiterYellow",
          "RainbowDelimiterBlue",
          "RainbowDelimiterOrange",
          "RainbowDelimiterGreen",
          "RainbowDelimiterViolet",
          "RainbowDelimiterCyan",
        },
      }
    end,
  },

  -----------------------------------------------------------------------------
  -- 3e. Indent-Blankline Rainbow Scope
  -----------------------------------------------------------------------------
  {
    "lukas-reineke/indent-blankline.nvim",
    opts = function(_, opts)
      local highlight = {
        "RainbowDelimiterRed",
        "RainbowDelimiterYellow",
        "RainbowDelimiterBlue",
        "RainbowDelimiterOrange",
        "RainbowDelimiterGreen",
        "RainbowDelimiterViolet",
        "RainbowDelimiterCyan",
      }
      opts.scope = opts.scope or {}
      opts.scope.highlight = highlight
    end,
    config = function(_, opts)
      require("ibl").setup(opts)
      local hooks = require("ibl.hooks")
      hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
    end,
  },

  -----------------------------------------------------------------------------
  -- 3f. Noice.nvim - Centered Command Palette
  -----------------------------------------------------------------------------
  {
    "folke/noice.nvim",
    opts = {
      presets = { lsp_doc_border = true },
      views = {
        cmdline_popup = {
          position = { row = "40%", col = "50%" },
          size = { width = 60, height = "auto" },
          border = { style = "rounded" },
        },
        popupmenu = {
          position = { row = "45%", col = "50%" },
          size = { width = 60, height = 10 },
          border = { style = "rounded" },
        },
      },
    },
  },

  -----------------------------------------------------------------------------
  -- 3h. Incline.nvim - Floating Window Filenames
  -----------------------------------------------------------------------------
  {
    "b0o/incline.nvim",
    event = "VeryLazy",
    opts = {
      window = {
        padding = 0,
        margin = { horizontal = 0 },
      },
      render = function(props)
        local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
        if filename == "" then
          filename = "[No Name]"
        end
        local ft_icon, ft_color = "", nil
        local ok, icons = pcall(require, "mini.icons")
        if ok then
          local icon, hl = icons.get("file", filename)
          if icon then
            ft_icon = icon
            local hl_fg = vim.api.nvim_get_hl(0, { name = hl }).fg
            if hl_fg then
              ft_color = string.format("#%06x", hl_fg)
            end
          end
        end
        local modified = vim.bo[props.buf].modified
        return {
          { " " },
          ft_icon ~= "" and { ft_icon .. " ", guifg = ft_color } or "",
          { filename, gui = modified and "bold,italic" or "bold" },
          { " " },
        }
      end,
    },
  },

  -----------------------------------------------------------------------------
  -- 3i. Which-Key - Rounded Borders
  -----------------------------------------------------------------------------
  {
    "folke/which-key.nvim",
    opts = {
      win = { border = "rounded" },
    },
  },

  -----------------------------------------------------------------------------
  -- 3j. Colorful Window Separators
  -----------------------------------------------------------------------------
  {
    "nvim-zh/colorful-winsep.nvim",
    event = "WinLeave",
    opts = function()
      -- The moving separator uses the theme accent, not WinSeparator: the
      -- static separator is a hairline on purpose, and a hairline that animates
      -- reads as a rendering glitch rather than a deliberate transition.
      local ok, roles = pcall(require, "atlas.roles")
      local fg = ok and roles.build().accent or "#3b6bff"
      return {
        hi = { fg = fg },
        smooth = true,
        exponential_smoothing = true,
      }
    end,
  },

  -----------------------------------------------------------------------------
  -- 3k. NVim Colorizer - Inline Color Previews
  -----------------------------------------------------------------------------
  {
    "NvChad/nvim-colorizer.lua",
    event = "BufReadPost",
    opts = {
      filetypes = { "*" },
      user_default_options = {
        names = false,
        css = true,
        css_fn = true,
        tailwind = true,
        mode = "virtualtext",
        virtualtext = "■",
      },
    },
  },
}
