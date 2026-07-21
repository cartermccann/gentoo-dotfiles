-- atlas.lualine — statusline theme built from the active atlas palette.
--
-- Shape mirrors the waybar chips: a solid accent block for the mode, a raised
-- chip either side of it, and a transparent middle so the compositor blur shows
-- through the same way it does in the buffer. Mode colour is the only thing
-- that changes between states, which is exactly the waybar rule -- colour means
-- "a state you must notice", everything else is monochrome.

local roles = require("atlas.roles")

return function()
  local c = roles.build()
  local transparent = vim.g.atlas_transparent ~= false
  local bg = transparent and "NONE" or c.bg

  -- a: the mode block. b: the chip beside it. c: the run.
  local function mode(colour)
    return {
      a = { fg = c.bg, bg = colour, gui = "bold" },
      b = { fg = c.fg, bg = c.raised },
      c = { fg = c.dim, bg = bg },
    }
  end

  return {
    normal = mode(c.accent),
    insert = mode(c.ok),
    visual = mode(c.ctrl),
    replace = mode(c.err),
    command = mode(c.fn),
    terminal = mode(c.type),
    inactive = {
      a = { fg = c.dim, bg = bg },
      b = { fg = c.dim, bg = bg },
      c = { fg = c.dim, bg = bg },
    },
  }
end
