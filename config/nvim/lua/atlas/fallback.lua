-- Baked-in cobalt palette.
--
-- `atlas-theme` generates lua/atlas/palette.lua from the active theme's
-- colors.sh. This file is what atlas.roles falls back to when that file is
-- missing -- a fresh checkout before the theme phase has run, a machine where
-- atlas-theme was never installed, or nvim launched from a rescue shell.
-- It is a verbatim copy of themes/cobalt/colors.sh so the editor always boots
-- themed instead of dumping you into nvim's default colours.
--
-- Keep in sync with themes/cobalt/colors.sh.
return {
  NAME = "Cobalt",
  MODE = "dark",

  GROUND = "0a0c11",
  BASE = "0f1218",
  SURFACE = "171b23",
  SURFACE2 = "212734",
  TEXT = "e7ebf2",
  SUBTEXT = "8b93a4",
  ACCENT = "3b6bff",
  ACCENT_INK = "cfe0ff",
  CURSOR = "3b6bff",

  T0 = "212734",
  T1 = "f87171",
  T2 = "34d399",
  T3 = "fbbf24",
  T4 = "3b6bff",
  T5 = "a78bfa",
  T6 = "22d3ee",
  T7 = "c7cdd8",
  T8 = "3a4152",
  T9 = "fca5a5",
  T10 = "6ee7b7",
  T11 = "fcd34d",
  T12 = "6b8fff",
  T13 = "c4b5fd",
  T14 = "67e8f9",
  T15 = "e7ebf2",
}
