#!/usr/bin/env bash
# Phase: theme — seed the atlas-theme switcher + themes, apply the default.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

step "atlas-theme switcher"
run mkdir -p "$HOME/.local/bin"
run chmod +x "$REPO_DIR/bin/atlas-theme" "$REPO_DIR/bin/atlas-wallpaper"
seed_copy "$REPO_DIR/bin/atlas-theme"     "$HOME/.local/bin/atlas-theme"
seed_copy "$REPO_DIR/bin/atlas-wallpaper" "$HOME/.local/bin/atlas-wallpaper"

step "themes"
# Live home for palettes (contract flipped 2026-08-05): atlas-theme reads
# ~/.local/share/atlas-theme/themes, never the repo. Adding a theme live is
# one themes/<name>/colors.sh there; --harvest carries it back to the seed.
seed_copy "$REPO_DIR/themes" "${XDG_DATA_HOME:-$HOME/.local/share}/atlas-theme/themes"

step "apply default theme (cobalt)"
# Generates ~/.config/*/theme.* so every app has colors on first login.
# Reload hooks no-op cleanly when no session is running yet.
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] atlas-theme set cobalt"
else
    "$HOME/.local/bin/atlas-theme" set cobalt \
        || warn "theme render had issues — re-run 'atlas-theme set cobalt' inside a Mango session"
fi

ok "theme phase complete"
info "switch: 'atlas-theme pick' (Super+Alt+T) · toggle light/dark (Super+Shift+T) · list: 'atlas-theme list'"
