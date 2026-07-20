#!/usr/bin/env bash
# Phase: theme — install the atlas-theme switcher and apply the default.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

step "atlas-theme switcher"
run mkdir -p "$HOME/.local/bin"
run chmod +x "$REPO_DIR/bin/atlas-theme"
backup_and_link "$REPO_DIR/bin/atlas-theme" "$HOME/.local/bin/atlas-theme"

step "apply default theme (cobalt)"
# Generates ~/.config/*/theme.* so every app has colors on first login.
# Reload hooks no-op cleanly when no session is running yet.
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] atlas-theme set cobalt"
else
    "$REPO_DIR/bin/atlas-theme" set cobalt \
        || warn "theme render had issues — re-run 'atlas-theme set cobalt' inside a Mango session"
fi

ok "theme phase complete"
info "switch: 'atlas-theme pick' (Super+Ctrl+T) · toggle light/dark (Super+Shift+T) · list: 'atlas-theme list'"
