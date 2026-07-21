-- atlas.roles — turns a 24-slot atlas palette into semantic editor roles.
--
-- The theme files (themes/<name>/colors.sh) describe a DESKTOP: a background,
-- a foreground, an accent, and the 16 ANSI terminal colours. That is not enough
-- vocabulary for code, which needs distinct hues for keywords, control flow,
-- functions, types, strings, numbers and identifiers all at once.
--
-- Rather than hand-author a colourscheme per theme (7 today, more later), every
-- role is DERIVED from the slots the theme already defines, using VS Code
-- Dark+ as the semantic reference:
--
--     keyword   blue    #569CD6      string    tan     #CE9178
--     control   mauve   #C586C0      number    sage    #B5CEA8
--     function  yellow  #DCDCAA      variable  pale bl #9CDCFE
--     type      teal    #4EC9B0      comment   green   #6A9955
--
-- The one primitive is `mix(colour, TEXT, t)` -- pull a hue toward the theme's
-- foreground. On a dark theme TEXT is near-white so this lightens and
-- desaturates; on a light theme (cobalt-light) TEXT is near-black so the exact
-- same expression darkens instead. That is why there is no separate light-mode
-- code path anywhere in this file.
--
-- Two hues the ANSI palette simply does not carry are built by blending:
--   string  wants an orange       -> yellow blended halfway into red
--   type    wants a teal          -> cyan blended toward green
--
-- Consequence: any future themes/<name>/colors.sh gets a full colourscheme for
-- free, with no edits here.

local M = {}

local function hex2rgb(h)
  h = h:gsub("^#", "")
  return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end

local function rgb2hex(r, g, b)
  local clamp = function(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
  return string.format("#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
end

--- Mix colour `a` toward colour `b` by `t` (0 = all a, 1 = all b).
local function mix(a, b, t)
  local ar, ag, ab = hex2rgb(a)
  local br, bg, bb = hex2rgb(b)
  return rgb2hex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end
M.mix = mix

--- Load the generated palette, falling back to baked-in cobalt.
function M.palette()
  package.loaded["atlas.palette"] = nil
  local ok, p = pcall(require, "atlas.palette")
  if not ok or type(p) ~= "table" or not p.BASE then
    p = require("atlas.fallback")
  end
  return p
end

--- Build the role table for a palette (defaults to the active one).
function M.build(p)
  p = p or M.palette()

  -- colors.sh stores bare hex ("0f1218"); normalise to "#0f1218".
  local h = setmetatable({}, {
    __index = function(_, k)
      local v = rawget(p, k)
      return v and ("#" .. tostring(v):gsub("^#", "")) or nil
    end,
  })

  local TEXT, BASE = h.TEXT, h.BASE
  local light = p.MODE == "light"

  local r = {
    mode = light and "light" or "dark",
    name = p.NAME or "Atlas",

    -- ── Surfaces ──
    ground = h.GROUND, -- desktop backdrop; nvim uses it for hard contrast
    bg = BASE,
    panel = h.SURFACE, -- floats, popups, statusline
    raised = h.SURFACE2, -- selection, active tab
    fg = TEXT,
    dim = h.SUBTEXT,
    accent = h.ACCENT,
    ink = h.ACCENT_INK,
    cursor = h.CURSOR or h.ACCENT,

    -- Cursorline has to be *just* visible over BASE without becoming a band.
    -- 0.45 toward SURFACE lands ~1 step above the background on every theme.
    cursorline = mix(BASE, h.SURFACE, 0.45),
    -- Line numbers. Pulled TOWARD text, not toward the background: on a dark
    -- theme SURFACE2 already sits close to BASE, so mixing that way collapses
    -- the gutter into the background and the numbers vanish.
    gutter = mix(h.SURFACE2, TEXT, 0.22),
    -- Listchars, `~` past end-of-buffer, fold markers: present but recessive.
    faint = mix(h.SURFACE2, TEXT, 0.10),
    -- Hairline separators and borders.
    hairline = h.SURFACE2,
    -- Indent guides, deliberately the quietest thing on screen.
    whitespace = mix(h.SURFACE2, BASE, 0.45),

    -- ── Syntax (VS Code Dark+ semantics) ──
    kw = mix(h.T4, TEXT, 0.28), -- const/let/function/class/interface
    ctrl = mix(h.T5, TEXT, 0.22), -- if/for/return/await/import/new
    fn = mix(h.T3, TEXT, 0.30), -- function + method names
    type = mix(mix(h.T6, h.T2, 0.40), TEXT, 0.12), -- types/classes/constructors
    str = mix(mix(h.T3, h.T1, 0.50), TEXT, 0.18), -- strings (derived orange)
    num = mix(h.T2, TEXT, 0.42), -- numbers
    var = mix(h.T4, TEXT, 0.55), -- variables/params/properties
    const = mix(h.T6, TEXT, 0.25), -- constants, enum members
    -- Comments: green, VS Code style. Dark+ #6A9955 is a notably DARK green
    -- against #1e1e1e -- comments are meant to recede -- so after desaturating
    -- the palette's green into SUBTEXT it gets pushed one more step away from
    -- the foreground. That second step is what keeps comments distinct from
    -- numbers on themes whose green is already olive (gruvbox, everforest);
    -- without it the two roles land within a few percent of each other.
    comment = mix(mix(h.T2, h.SUBTEXT, 0.45), light and TEXT or BASE, 0.22),
    op = h.SUBTEXT, -- operators/punctuation (dimmed, not fg)
    regex = mix(h.T1, TEXT, 0.30),
    escape = mix(h.T3, TEXT, 0.20),

    -- ── Semantic states ──
    err = h.T1,
    warn = h.T3,
    info = h.T6,
    hint = h.T5,
    ok = h.T2,
  }

  -- Diagnostic virtual-text washes: the state colour pulled almost all the way
  -- into the background, so the tint reads without competing with the code.
  local wash = light and 0.90 or 0.86
  r.err_bg = mix(r.err, BASE, wash)
  r.warn_bg = mix(r.warn, BASE, wash)
  r.info_bg = mix(r.info, BASE, wash)
  r.hint_bg = mix(r.hint, BASE, wash)
  r.ok_bg = mix(r.ok, BASE, wash)

  -- Diff blocks need a touch more presence than diagnostics.
  local dwash = light and 0.84 or 0.78
  r.diff_add = mix(r.ok, BASE, dwash)
  r.diff_del = mix(r.err, BASE, dwash)
  r.diff_chg = mix(r.accent, BASE, dwash)
  r.diff_txt = mix(r.accent, BASE, light and 0.68 or 0.60)

  -- Visual selection: accent-tinted, never so strong it hides the text under it.
  r.sel = mix(h.SURFACE2, r.accent, light and 0.12 or 0.18)
  r.search = mix(r.warn, BASE, light and 0.70 or 0.68)
  r.match = mix(h.SURFACE2, r.accent, 0.28)

  return r
end

return M
