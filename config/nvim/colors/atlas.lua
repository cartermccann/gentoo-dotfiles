-- atlas — theme-aware colourscheme for the atlas desktop.
--
--   themes/<name>/colors.sh          the palette (one file per theme)
--          |  atlas-theme set <name>
--          v
--   lua/atlas/palette.lua            generated; raw slots only
--          |  require("atlas.roles")
--          v
--   colors/atlas.lua                 this file; roles -> highlight groups
--
-- Nothing here hardcodes a colour. Every group asks `atlas.roles` for a role
-- (keyword, string, function, ...) and the roles are derived from whichever
-- theme is currently active, so `atlas-theme set nord` recolours the editor to
-- match waybar, ghostty, rofi and the compositor borders in the same keystroke.
-- A filesystem watcher (bottom of this file) re-sources on write, so a running
-- nvim recolours live -- it does not wait for a restart.
--
-- Syntax semantics follow VS Code Dark+ (see lua/atlas/roles.lua for the
-- mapping and why each role is derived rather than hardcoded), with two
-- deliberate departures:
--
--   * operators and punctuation are dimmed to SUBTEXT rather than left at full
--     foreground. Dark+ paints them #D4D4D4, identical to plain text, which
--     makes dense TypeScript read as a wall. Dimming them lets structure
--     recede and names carry the line.
--   * comments are green (Dark+ #6A9955) but derived per-theme by blending the
--     palette's green into SUBTEXT, so gruvbox gets a gruvbox green rather
--     than a foreign one.
--
-- Transparency defaults ON so the background comes from mango's blur, matching
-- ghostty and the rest of the glass idiom. Set `vim.g.atlas_transparent = false`
-- before `:colorscheme atlas` for a solid background, or toggle it live with
-- <leader>uh.

vim.cmd("hi clear")
if vim.fn.exists("syntax_on") then
  vim.cmd("syntax reset")
end

-- Drop the cached modules so a re-source picks up a freshly written palette.
package.loaded["atlas.roles"] = nil
package.loaded["atlas.palette"] = nil

local roles = require("atlas.roles")
local c = roles.build()

vim.o.background = c.mode
vim.g.colors_name = "atlas"

local transparent = vim.g.atlas_transparent ~= false
local NONE = "NONE"

-- Normal background: transparent lets the compositor blur through. Floats stay
-- solid regardless, or they lose their edge against the buffer behind them.
local NB = transparent and NONE or c.bg
local FB = c.panel

local function hl(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- ═══ Editor ═══════════════════════════════════════════════════
hl("Normal", { fg = c.fg, bg = NB })
hl("NormalNC", { fg = c.fg, bg = NB })
hl("NormalFloat", { fg = c.fg, bg = FB })
hl("FloatBorder", { fg = c.hairline, bg = FB })
hl("FloatTitle", { fg = c.accent, bg = FB, bold = true })
hl("Visual", { bg = c.sel })
hl("VisualNOS", { bg = c.sel })
hl("Search", { fg = c.fg, bg = c.search })
hl("IncSearch", { fg = c.bg, bg = c.accent, bold = true })
hl("CurSearch", { fg = c.bg, bg = c.accent, bold = true })
hl("Substitute", { fg = c.bg, bg = c.warn })
hl("CursorLine", { bg = c.cursorline })
hl("CursorColumn", { bg = c.cursorline })
hl("ColorColumn", { bg = c.panel })
hl("LineNr", { fg = c.gutter })
hl("LineNrAbove", { fg = c.gutter })
hl("LineNrBelow", { fg = c.gutter })
hl("CursorLineNr", { fg = c.accent, bold = true })
hl("CursorLineSign", { bg = c.cursorline })
hl("CursorLineFold", { bg = c.cursorline })
hl("SignColumn", { fg = c.dim, bg = NB })
hl("FoldColumn", { fg = c.faint, bg = NB })
hl("Folded", { fg = c.dim, bg = c.panel })
hl("VertSplit", { fg = c.hairline })
hl("WinSeparator", { fg = c.hairline })
hl("StatusLine", { fg = c.fg, bg = c.panel })
hl("StatusLineNC", { fg = c.dim, bg = c.panel })
hl("TabLine", { fg = c.dim, bg = c.panel })
hl("TabLineSel", { fg = c.accent, bg = NB, bold = true })
hl("TabLineFill", { bg = NB })
hl("WinBar", { fg = c.fg, bg = NB })
hl("WinBarNC", { fg = c.dim, bg = NB })
hl("Pmenu", { fg = c.fg, bg = FB })
hl("PmenuSel", { fg = c.fg, bg = c.sel, bold = true })
hl("PmenuSbar", { bg = c.raised })
hl("PmenuThumb", { bg = c.dim })
hl("WildMenu", { fg = c.bg, bg = c.accent })
hl("Directory", { fg = c.accent })
hl("Title", { fg = c.accent, bold = true })
hl("MatchParen", { fg = c.accent, bg = c.match, bold = true })
hl("NonText", { fg = c.faint })
hl("SpecialKey", { fg = c.faint })
hl("Whitespace", { fg = c.whitespace })
hl("EndOfBuffer", { fg = c.bg })
hl("Conceal", { fg = c.dim })
hl("QuickFixLine", { bg = c.sel })
hl("MsgArea", { fg = c.fg })
hl("MsgSeparator", { fg = c.hairline })
hl("ModeMsg", { fg = c.accent, bold = true })
hl("MoreMsg", { fg = c.ok })
hl("Question", { fg = c.ok })
hl("WarningMsg", { fg = c.warn })
hl("ErrorMsg", { fg = c.err, bold = true })

-- ═══ Cursor ═══════════════════════════════════════════════════
hl("Cursor", { fg = c.bg, bg = c.cursor })
hl("lCursor", { fg = c.bg, bg = c.cursor })
hl("CursorIM", { fg = c.bg, bg = c.cursor })
hl("TermCursor", { fg = c.bg, bg = c.cursor })
hl("TermCursorNC", { fg = c.bg, bg = c.dim })

-- ═══ Diff ═════════════════════════════════════════════════════
hl("DiffAdd", { bg = c.diff_add })
hl("DiffChange", { bg = c.diff_chg })
hl("DiffDelete", { fg = c.err, bg = c.diff_del })
hl("DiffText", { bg = c.diff_txt })

-- ═══ Spell ════════════════════════════════════════════════════
hl("SpellBad", { undercurl = true, sp = c.err })
hl("SpellCap", { undercurl = true, sp = c.warn })
hl("SpellRare", { undercurl = true, sp = c.hint })
hl("SpellLocal", { undercurl = true, sp = c.info })

-- ═══ Legacy syntax ════════════════════════════════════════════
hl("Comment", { fg = c.comment, italic = true })
hl("Constant", { fg = c.const })
hl("String", { fg = c.str })
hl("Character", { fg = c.str })
hl("Number", { fg = c.num })
hl("Float", { fg = c.num })
hl("Boolean", { fg = c.kw }) -- Dark+ paints true/false as keywords
hl("Identifier", { fg = c.var })
hl("Function", { fg = c.fn })
hl("Statement", { fg = c.ctrl })
hl("Conditional", { fg = c.ctrl })
hl("Repeat", { fg = c.ctrl })
hl("Label", { fg = c.ctrl })
hl("Operator", { fg = c.op })
hl("Keyword", { fg = c.kw })
hl("Exception", { fg = c.ctrl })
hl("PreProc", { fg = c.ctrl })
hl("Include", { fg = c.ctrl })
hl("Define", { fg = c.ctrl })
hl("Macro", { fg = c.ctrl })
hl("PreCondit", { fg = c.ctrl })
hl("Type", { fg = c.type })
hl("StorageClass", { fg = c.kw })
hl("Structure", { fg = c.type })
hl("Typedef", { fg = c.type })
hl("Special", { fg = c.escape })
hl("SpecialChar", { fg = c.escape })
hl("Tag", { fg = c.type })
hl("Delimiter", { fg = c.op })
hl("SpecialComment", { fg = c.comment, bold = true })
hl("Debug", { fg = c.warn })
hl("Underlined", { fg = c.info, underline = true })
hl("Ignore", { fg = c.dim })
hl("Error", { fg = c.err, bold = true })
hl("Todo", { fg = c.bg, bg = c.warn, bold = true })

-- ═══ Treesitter ═══════════════════════════════════════════════
hl("@comment", { link = "Comment" })
hl("@comment.error", { fg = c.bg, bg = c.err, bold = true })
hl("@comment.warning", { fg = c.bg, bg = c.warn, bold = true })
hl("@comment.todo", { link = "Todo" })
hl("@comment.note", { fg = c.bg, bg = c.info, bold = true })

hl("@constant", { fg = c.const })
hl("@constant.builtin", { fg = c.kw })
hl("@constant.macro", { fg = c.ctrl })

hl("@string", { fg = c.str })
hl("@string.documentation", { fg = c.str })
hl("@string.escape", { fg = c.escape, bold = true })
hl("@string.regexp", { fg = c.regex })
hl("@string.special", { fg = c.escape })
hl("@string.special.url", { fg = c.info, underline = true })
hl("@string.special.path", { fg = c.str, underline = true })
hl("@character", { fg = c.str })
hl("@character.special", { fg = c.escape })

hl("@number", { fg = c.num })
hl("@number.float", { fg = c.num })
hl("@boolean", { fg = c.kw })

hl("@function", { fg = c.fn })
hl("@function.builtin", { fg = c.fn })
hl("@function.call", { fg = c.fn })
hl("@function.macro", { fg = c.ctrl })
hl("@function.method", { fg = c.fn })
hl("@function.method.call", { fg = c.fn })
hl("@method", { fg = c.fn })
hl("@method.call", { fg = c.fn })
hl("@constructor", { fg = c.type })

-- Storage / declaration keywords stay blue; control flow goes mauve.
hl("@keyword", { fg = c.kw })
hl("@keyword.function", { fg = c.kw })
hl("@keyword.type", { fg = c.kw })
hl("@keyword.modifier", { fg = c.kw })
hl("@keyword.operator", { fg = c.kw })
hl("@keyword.return", { fg = c.ctrl })
hl("@keyword.import", { fg = c.ctrl })
hl("@keyword.export", { fg = c.ctrl })
hl("@keyword.conditional", { fg = c.ctrl })
hl("@keyword.conditional.ternary", { fg = c.op })
hl("@keyword.repeat", { fg = c.ctrl })
hl("@keyword.exception", { fg = c.ctrl })
hl("@keyword.coroutine", { fg = c.ctrl })
hl("@keyword.debug", { fg = c.ctrl })
hl("@keyword.directive", { fg = c.ctrl })
hl("@keyword.directive.define", { fg = c.ctrl })
hl("@conditional", { fg = c.ctrl })
hl("@repeat", { fg = c.ctrl })
hl("@exception", { fg = c.ctrl })
hl("@include", { fg = c.ctrl })
hl("@label", { fg = c.ctrl })

hl("@operator", { fg = c.op })
hl("@punctuation.bracket", { fg = c.op })
hl("@punctuation.delimiter", { fg = c.op })
hl("@punctuation.special", { fg = c.escape })

hl("@type", { fg = c.type })
hl("@type.builtin", { fg = c.type })
hl("@type.definition", { fg = c.type })
hl("@type.qualifier", { fg = c.kw })

hl("@module", { fg = c.type })
hl("@module.builtin", { fg = c.type })
hl("@namespace", { fg = c.type })

hl("@variable", { fg = c.var })
hl("@variable.builtin", { fg = c.kw, italic = true }) -- this / self
hl("@variable.parameter", { fg = c.var })
hl("@variable.parameter.builtin", { fg = c.var, italic = true })
hl("@variable.member", { fg = c.var })
hl("@property", { fg = c.var })
hl("@field", { fg = c.var })
hl("@parameter", { fg = c.var })
hl("@attribute", { fg = c.fn })
hl("@attribute.builtin", { fg = c.fn })

hl("@tag", { fg = c.type })
hl("@tag.builtin", { fg = c.type })
hl("@tag.attribute", { fg = c.var, italic = true })
hl("@tag.delimiter", { fg = c.op })

-- ── Markup (markdown, help, docstrings) ──
hl("@markup", { fg = c.fg })
hl("@markup.strong", { fg = c.fg, bold = true })
hl("@markup.italic", { italic = true })
hl("@markup.underline", { underline = true })
hl("@markup.strikethrough", { strikethrough = true })
hl("@markup.heading", { fg = c.accent, bold = true })
hl("@markup.heading.1", { fg = c.accent, bold = true })
hl("@markup.heading.2", { fg = c.type, bold = true })
hl("@markup.heading.3", { fg = c.fn, bold = true })
hl("@markup.heading.4", { fg = c.ctrl, bold = true })
hl("@markup.heading.5", { fg = c.var, bold = true })
hl("@markup.heading.6", { fg = c.dim, bold = true })
hl("@markup.quote", { fg = c.dim, italic = true })
hl("@markup.math", { fg = c.const })
hl("@markup.link", { fg = c.info, underline = true })
hl("@markup.link.url", { fg = c.info, underline = true })
hl("@markup.link.label", { fg = c.ctrl })
hl("@markup.raw", { fg = c.str })
hl("@markup.raw.block", { fg = c.fg })
hl("@markup.list", { fg = c.accent })
hl("@markup.list.checked", { fg = c.ok })
hl("@markup.list.unchecked", { fg = c.dim })

hl("@diff.plus", { fg = c.ok })
hl("@diff.minus", { fg = c.err })
hl("@diff.delta", { fg = c.accent })

-- ═══ LSP semantic tokens ══════════════════════════════════════
hl("@lsp.type.namespace", { link = "@module" })
hl("@lsp.type.type", { link = "@type" })
hl("@lsp.type.class", { link = "@type" })
hl("@lsp.type.enum", { link = "@type" })
hl("@lsp.type.interface", { link = "@type" })
hl("@lsp.type.struct", { link = "@type" })
hl("@lsp.type.typeParameter", { fg = c.type, italic = true })
hl("@lsp.type.parameter", { link = "@variable.parameter" })
hl("@lsp.type.variable", { link = "@variable" })
hl("@lsp.type.property", { link = "@property" })
hl("@lsp.type.enumMember", { fg = c.const })
hl("@lsp.type.function", { link = "@function" })
hl("@lsp.type.method", { link = "@function.method" })
hl("@lsp.type.macro", { link = "@function.macro" })
hl("@lsp.type.decorator", { link = "@attribute" })
hl("@lsp.type.keyword", { link = "@keyword" })
hl("@lsp.type.comment", { link = "@comment" })
hl("@lsp.type.string", { link = "@string" })
hl("@lsp.type.number", { link = "@number" })
hl("@lsp.type.operator", { link = "@operator" })
hl("@lsp.typemod.variable.readonly", { fg = c.const })
hl("@lsp.typemod.variable.defaultLibrary", { fg = c.kw })
hl("@lsp.typemod.function.defaultLibrary", { fg = c.fn })
hl("@lsp.typemod.method.defaultLibrary", { fg = c.fn })
hl("@lsp.typemod.keyword.async", { fg = c.ctrl })
hl("@lsp.mod.deprecated", { strikethrough = true })

-- ═══ Diagnostics ══════════════════════════════════════════════
hl("DiagnosticError", { fg = c.err })
hl("DiagnosticWarn", { fg = c.warn })
hl("DiagnosticInfo", { fg = c.info })
hl("DiagnosticHint", { fg = c.hint })
hl("DiagnosticOk", { fg = c.ok })
hl("DiagnosticUnderlineError", { undercurl = true, sp = c.err })
hl("DiagnosticUnderlineWarn", { undercurl = true, sp = c.warn })
hl("DiagnosticUnderlineInfo", { undercurl = true, sp = c.info })
hl("DiagnosticUnderlineHint", { undercurl = true, sp = c.hint })
hl("DiagnosticUnderlineOk", { undercurl = true, sp = c.ok })
hl("DiagnosticVirtualTextError", { fg = c.err, bg = c.err_bg })
hl("DiagnosticVirtualTextWarn", { fg = c.warn, bg = c.warn_bg })
hl("DiagnosticVirtualTextInfo", { fg = c.info, bg = c.info_bg })
hl("DiagnosticVirtualTextHint", { fg = c.hint, bg = c.hint_bg })
hl("DiagnosticVirtualTextOk", { fg = c.ok, bg = c.ok_bg })

-- ═══ LSP ══════════════════════════════════════════════════════
hl("LspReferenceText", { bg = c.match })
hl("LspReferenceRead", { bg = c.match })
hl("LspReferenceWrite", { bg = c.match, underline = true })
hl("LspSignatureActiveParameter", { fg = c.accent, bold = true })
hl("LspInlayHint", { fg = c.dim, bg = c.panel, italic = true })
hl("LspCodeLens", { fg = c.dim, italic = true })
hl("LspCodeLensSeparator", { fg = c.hairline })

-- ═══ AI ghost text ════════════════════════════════════════════
hl("MinuetVirtualText", { fg = c.dim, italic = true })
hl("ComplHint", { fg = c.dim, italic = true })
hl("ComplHintMore", { fg = c.dim, italic = true })

-- ═══ Git ══════════════════════════════════════════════════════
hl("GitSignsAdd", { fg = c.ok })
hl("GitSignsChange", { fg = c.accent })
hl("GitSignsDelete", { fg = c.err })
hl("GitSignsAddNr", { fg = c.ok })
hl("GitSignsChangeNr", { fg = c.accent })
hl("GitSignsDeleteNr", { fg = c.err })
hl("GitSignsAddInline", { bg = c.diff_add })
hl("GitSignsChangeInline", { bg = c.diff_chg })
hl("GitSignsDeleteInline", { bg = c.diff_del })
hl("Added", { fg = c.ok })
hl("Changed", { fg = c.accent })
hl("Removed", { fg = c.err })

-- ═══ Telescope ════════════════════════════════════════════════
hl("TelescopeNormal", { fg = c.fg, bg = FB })
hl("TelescopeBorder", { fg = c.hairline, bg = FB })
hl("TelescopeTitle", { fg = c.accent, bold = true })
hl("TelescopeSelection", { bg = c.sel })
hl("TelescopeSelectionCaret", { fg = c.accent })
hl("TelescopeMatching", { fg = c.accent, bold = true })
hl("TelescopePromptPrefix", { fg = c.accent })
hl("TelescopePromptNormal", { fg = c.fg, bg = FB })
hl("TelescopePromptBorder", { fg = c.hairline, bg = FB })
hl("TelescopeResultsNormal", { fg = c.fg, bg = FB })
hl("TelescopeResultsBorder", { fg = c.hairline, bg = FB })
hl("TelescopePreviewNormal", { fg = c.fg, bg = FB })
hl("TelescopePreviewBorder", { fg = c.hairline, bg = FB })

-- ═══ Neo-tree ═════════════════════════════════════════════════
hl("NeoTreeNormal", { fg = c.fg, bg = NB })
hl("NeoTreeNormalNC", { fg = c.fg, bg = NB })
hl("NeoTreeWinSeparator", { fg = c.hairline, bg = NB })
hl("NeoTreeEndOfBuffer", { fg = c.bg, bg = NB })
hl("NeoTreeDirectoryName", { fg = c.accent })
hl("NeoTreeDirectoryIcon", { fg = c.accent })
hl("NeoTreeRootName", { fg = c.accent, bold = true })
hl("NeoTreeFileName", { fg = c.fg })
hl("NeoTreeFileNameOpened", { fg = c.fg, bold = true })
hl("NeoTreeGitModified", { fg = c.accent })
hl("NeoTreeGitDirty", { fg = c.accent })
hl("NeoTreeGitUntracked", { fg = c.ok })
hl("NeoTreeGitAdded", { fg = c.ok })
hl("NeoTreeGitDeleted", { fg = c.err })
hl("NeoTreeGitConflict", { fg = c.warn })
hl("NeoTreeIndentMarker", { fg = c.whitespace })
hl("NeoTreeExpander", { fg = c.dim })
hl("NeoTreeDimText", { fg = c.dim })
hl("NeoTreeTabActive", { fg = c.accent, bold = true })
hl("NeoTreeTabInactive", { fg = c.dim })
hl("NeoTreeTabSeparatorActive", { fg = c.accent })
hl("NeoTreeTabSeparatorInactive", { fg = c.hairline })

-- ═══ Indent guides ════════════════════════════════════════════
hl("IblIndent", { fg = c.whitespace })
hl("IblScope", { fg = c.hairline })
hl("IndentBlanklineChar", { fg = c.whitespace })
hl("IndentBlanklineContextChar", { fg = c.hairline })
hl("SnacksIndent", { fg = c.whitespace })
hl("SnacksIndentScope", { fg = c.accent })

-- ═══ Rainbow delimiters ═══════════════════════════════════════
-- Rotates through the syntax roles rather than raw ANSI, so nesting depth
-- stays legible in every theme instead of flashing saturated primaries.
hl("RainbowDelimiterRed", { fg = c.err })
hl("RainbowDelimiterYellow", { fg = c.fn })
hl("RainbowDelimiterBlue", { fg = c.kw })
hl("RainbowDelimiterOrange", { fg = c.str })
hl("RainbowDelimiterGreen", { fg = c.num })
hl("RainbowDelimiterViolet", { fg = c.ctrl })
hl("RainbowDelimiterCyan", { fg = c.type })

-- ═══ Which-key ════════════════════════════════════════════════
hl("WhichKey", { fg = c.accent, bold = true })
hl("WhichKeyGroup", { fg = c.type })
hl("WhichKeyDesc", { fg = c.fg })
hl("WhichKeyIcon", { fg = c.var })
hl("WhichKeySeparator", { fg = c.dim })
hl("WhichKeyNormal", { bg = FB })
hl("WhichKeyFloat", { bg = FB })
hl("WhichKeyBorder", { fg = c.hairline, bg = FB })
hl("WhichKeyTitle", { fg = c.accent, bg = FB, bold = true })
hl("WhichKeyValue", { fg = c.dim })

-- ═══ Noice ════════════════════════════════════════════════════
hl("NoiceCmdline", { fg = c.fg })
hl("NoiceCmdlinePopup", { fg = c.fg, bg = FB })
hl("NoiceCmdlinePopupBorder", { fg = c.accent, bg = FB })
hl("NoiceCmdlinePopupTitle", { fg = c.accent, bg = FB, bold = true })
hl("NoiceCmdlineIcon", { fg = c.accent })
hl("NoiceCmdlineIconSearch", { fg = c.warn })
hl("NoicePopupmenu", { fg = c.fg, bg = FB })
hl("NoicePopupmenuBorder", { fg = c.hairline, bg = FB })
hl("NoicePopupmenuSelected", { bg = c.sel, bold = true })
hl("NoicePopupmenuMatch", { fg = c.accent, bold = true })
hl("NoiceConfirm", { fg = c.fg, bg = FB })
hl("NoiceConfirmBorder", { fg = c.hairline, bg = FB })
hl("NoiceMini", { fg = c.dim, bg = FB })
hl("NoiceVirtualText", { fg = c.dim, italic = true })

-- ═══ Snacks (dashboard, notifier, picker, input) ══════════════
hl("SnacksDashboardHeader", { fg = c.accent, bold = true })
hl("SnacksDashboardIcon", { fg = c.var })
hl("SnacksDashboardKey", { fg = c.accent, bold = true })
hl("SnacksDashboardDesc", { fg = c.fg })
hl("SnacksDashboardFile", { fg = c.fg })
hl("SnacksDashboardDir", { fg = c.dim })
hl("SnacksDashboardFooter", { fg = c.comment, italic = true })
hl("SnacksDashboardTitle", { fg = c.accent, bold = true })
hl("SnacksDashboardSpecial", { fg = c.type })
hl("SnacksDashboardTerminal", { fg = c.accent })
hl("SnacksNotifierInfo", { fg = c.info })
hl("SnacksNotifierWarn", { fg = c.warn })
hl("SnacksNotifierError", { fg = c.err })
hl("SnacksNotifierDebug", { fg = c.dim })
hl("SnacksNotifierTrace", { fg = c.hint })
hl("SnacksNotifierBorderInfo", { fg = c.info, bg = FB })
hl("SnacksNotifierBorderWarn", { fg = c.warn, bg = FB })
hl("SnacksNotifierBorderError", { fg = c.err, bg = FB })
hl("SnacksNormal", { fg = c.fg, bg = FB })
hl("SnacksWinBar", { fg = c.accent, bg = FB, bold = true })
hl("SnacksBackdrop", { bg = c.ground })
hl("SnacksPickerMatch", { fg = c.accent, bold = true })
hl("SnacksPickerDir", { fg = c.dim })
hl("SnacksPickerTitle", { fg = c.accent, bold = true })
hl("SnacksPickerBorder", { fg = c.hairline, bg = FB })
hl("SnacksPickerPrompt", { fg = c.accent })
hl("SnacksPickerListCursorLine", { bg = c.sel })
hl("SnacksInputBorder", { fg = c.accent, bg = FB })
hl("SnacksInputTitle", { fg = c.accent, bg = FB, bold = true })

-- ═══ blink.cmp ════════════════════════════════════════════════
hl("BlinkCmpMenu", { fg = c.fg, bg = FB })
hl("BlinkCmpMenuBorder", { fg = c.hairline, bg = FB })
hl("BlinkCmpMenuSelection", { bg = c.sel })
hl("BlinkCmpScrollBarThumb", { bg = c.raised })
hl("BlinkCmpScrollBarGutter", { bg = FB })
hl("BlinkCmpLabel", { fg = c.fg })
hl("BlinkCmpLabelMatch", { fg = c.accent, bold = true })
hl("BlinkCmpLabelDetail", { fg = c.dim })
hl("BlinkCmpLabelDescription", { fg = c.dim })
hl("BlinkCmpLabelDeprecated", { fg = c.dim, strikethrough = true })
hl("BlinkCmpKind", { fg = c.var })
hl("BlinkCmpKindFunction", { fg = c.fn })
hl("BlinkCmpKindMethod", { fg = c.fn })
hl("BlinkCmpKindConstructor", { fg = c.type })
hl("BlinkCmpKindClass", { fg = c.type })
hl("BlinkCmpKindInterface", { fg = c.type })
hl("BlinkCmpKindStruct", { fg = c.type })
hl("BlinkCmpKindEnum", { fg = c.type })
hl("BlinkCmpKindEnumMember", { fg = c.const })
hl("BlinkCmpKindKeyword", { fg = c.kw })
hl("BlinkCmpKindVariable", { fg = c.var })
hl("BlinkCmpKindField", { fg = c.var })
hl("BlinkCmpKindProperty", { fg = c.var })
hl("BlinkCmpKindConstant", { fg = c.const })
hl("BlinkCmpKindText", { fg = c.fg })
hl("BlinkCmpKindSnippet", { fg = c.ok })
hl("BlinkCmpKindFile", { fg = c.accent })
hl("BlinkCmpKindFolder", { fg = c.accent })
hl("BlinkCmpSource", { fg = c.dim })
hl("BlinkCmpDoc", { fg = c.fg, bg = FB })
hl("BlinkCmpDocBorder", { fg = c.hairline, bg = FB })
hl("BlinkCmpDocSeparator", { fg = c.hairline, bg = FB })
hl("BlinkCmpSignatureHelp", { fg = c.fg, bg = FB })
hl("BlinkCmpSignatureHelpBorder", { fg = c.hairline, bg = FB })
hl("BlinkCmpSignatureHelpActiveParameter", { fg = c.accent, bold = true })
hl("BlinkCmpGhostText", { fg = c.dim, italic = true })

-- ═══ Flash ════════════════════════════════════════════════════
hl("FlashLabel", { fg = c.bg, bg = c.accent, bold = true })
hl("FlashMatch", { fg = c.fg, bg = c.match })
hl("FlashCurrent", { fg = c.bg, bg = c.info, bold = true })
hl("FlashBackdrop", { fg = c.dim })

-- ═══ Mini icons ═══════════════════════════════════════════════
hl("MiniIconsAzure", { fg = c.accent })
hl("MiniIconsBlue", { fg = c.kw })
hl("MiniIconsCyan", { fg = c.type })
hl("MiniIconsGreen", { fg = c.num })
hl("MiniIconsGrey", { fg = c.dim })
hl("MiniIconsOrange", { fg = c.str })
hl("MiniIconsPurple", { fg = c.ctrl })
hl("MiniIconsRed", { fg = c.err })
hl("MiniIconsYellow", { fg = c.fn })

-- ═══ Bufferline ═══════════════════════════════════════════════
hl("BufferLineFill", { bg = NB })
hl("BufferLineBackground", { fg = c.dim, bg = NB })
hl("BufferLineBufferVisible", { fg = c.dim, bg = NB })
hl("BufferLineBufferSelected", { fg = c.accent, bg = NB, bold = true })
hl("BufferLineModified", { fg = c.ok, bg = NB })
hl("BufferLineModifiedVisible", { fg = c.ok, bg = NB })
hl("BufferLineModifiedSelected", { fg = c.ok, bg = NB })
hl("BufferLineIndicatorSelected", { fg = c.accent, bg = NB })
hl("BufferLineSeparator", { fg = c.bg, bg = NB })
hl("BufferLineSeparatorVisible", { fg = c.bg, bg = NB })
hl("BufferLineSeparatorSelected", { fg = c.bg, bg = NB })
hl("BufferLineCloseButton", { fg = c.dim, bg = NB })
hl("BufferLineCloseButtonSelected", { fg = c.err, bg = NB })
hl("BufferLineNumbers", { fg = c.dim, bg = NB })
hl("BufferLineNumbersSelected", { fg = c.accent, bg = NB, bold = true })

-- ═══ Lazy ═════════════════════════════════════════════════════
hl("LazyNormal", { fg = c.fg, bg = FB })
hl("LazyButton", { fg = c.fg, bg = c.raised })
hl("LazyButtonActive", { fg = c.bg, bg = c.accent, bold = true })
hl("LazyH1", { fg = c.bg, bg = c.accent, bold = true })
hl("LazyH2", { fg = c.accent, bold = true })
hl("LazySpecial", { fg = c.accent })
hl("LazyProgressDone", { fg = c.ok })
hl("LazyProgressTodo", { fg = c.raised })
hl("LazyReasonPlugin", { fg = c.ctrl })
hl("LazyReasonEvent", { fg = c.fn })
hl("LazyReasonKeys", { fg = c.type })
hl("LazyDimmed", { fg = c.dim })

-- ═══ Mason ════════════════════════════════════════════════════
hl("MasonNormal", { fg = c.fg, bg = FB })
hl("MasonHeader", { fg = c.bg, bg = c.accent, bold = true })
hl("MasonHighlight", { fg = c.accent })
hl("MasonHighlightBlock", { fg = c.bg, bg = c.accent })
hl("MasonHighlightBlockBold", { fg = c.bg, bg = c.accent, bold = true })
hl("MasonMuted", { fg = c.dim })
hl("MasonMutedBlock", { fg = c.fg, bg = c.raised })

-- ═══ Trouble ══════════════════════════════════════════════════
hl("TroubleNormal", { fg = c.fg, bg = NB })
hl("TroubleText", { fg = c.fg })
hl("TroubleCount", { fg = c.accent, bg = c.raised })
hl("TroubleIndent", { fg = c.whitespace })

-- ═══ Diffview ═════════════════════════════════════════════════
hl("DiffviewNormal", { link = "Normal" })
hl("DiffviewFilePanelTitle", { fg = c.accent, bold = true })
hl("DiffviewFilePanelCounter", { fg = c.ctrl })
hl("DiffviewFilePanelFileName", { fg = c.fg })
hl("DiffviewFilePanelRootPath", { fg = c.dim })
hl("DiffviewStatusAdded", { fg = c.ok })
hl("DiffviewStatusModified", { fg = c.accent })
hl("DiffviewStatusDeleted", { fg = c.err })

-- ═══ Treesitter context ═══════════════════════════════════════
hl("TreesitterContext", { bg = c.panel })
hl("TreesitterContextLineNumber", { fg = c.gutter, bg = c.panel })
hl("TreesitterContextBottom", { underline = true, sp = c.hairline })

-- ═══ Terminal ANSI ════════════════════════════════════════════
-- Straight from the theme's 16 slots so :terminal matches ghostty exactly.
local p = roles.palette()
for i = 0, 15 do
  vim.g["terminal_color_" .. i] = "#" .. tostring(p["T" .. i]):gsub("^#", "")
end

-- ═══ Live reload ══════════════════════════════════════════════
-- `atlas-theme set <name>` rewrites lua/atlas/palette.lua. Watch for that and
-- re-source, so switching themes recolours a running nvim the same way it
-- recolours waybar and swaync -- no restart, no :colorscheme by hand.
--
-- The DIRECTORY is watched, not the file: the palette is written via tmp+rename
-- for atomicity, which swaps the inode out from under a file-level watch after
-- the first switch. A directory watch survives that.
-- The handle is parked on _G because this file is a script, not a module: a
-- local would fall out of scope at the end of the sourcing and the watcher
-- would stop the moment it was collected.
if not _G.__atlas_palette_watcher then
  local dir = vim.fn.stdpath("config") .. "/lua/atlas"
  local handle = (vim.uv or vim.loop).new_fs_event()
  if handle then
    local pending = false
    local started = pcall(function()
      handle:start(dir, {}, function(err, fname)
        if err or fname ~= "palette.lua" or pending then
          return
        end
        -- Coalesce the write/rename burst into a single reload.
        pending = true
        vim.defer_fn(function()
          pending = false
          if (vim.g.colors_name or "") == "atlas" then
            pcall(vim.cmd.colorscheme, "atlas")
          end
        end, 120)
      end)
    end)
    if started then
      _G.__atlas_palette_watcher = handle
    else
      handle:close()
    end
  end
end
