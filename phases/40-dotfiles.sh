#!/usr/bin/env bash
# Phase: dotfiles — symlink configs, pull nvim, set up shell.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

# ── Symlink every config/<app> into ~/.config/<app> ────────────
step "link configs into ~/.config"
for dir in "$REPO_DIR"/config/*/; do
    name="$(basename "$dir")"
    backup_and_link "${dir%/}" "$HOME/.config/$name"
done

# ── Make mango scripts executable ──────────────────────────────
step "executable bits"
run chmod +x "$REPO_DIR"/config/mango/autostart.sh "$REPO_DIR"/config/mango/scripts/*.sh 2>/dev/null
ok "mango scripts executable"

# ── Dictation (Parakeet) scripts → ~/.local/bin ────────────────
step "dictation (Parakeet) scripts"
run mkdir -p "$HOME/.local/bin"
run chmod +x "$REPO_DIR"/dictation/*.sh
backup_and_link "$REPO_DIR/dictation/toggle-dictation.sh" "$HOME/.local/bin/toggle-dictation.sh"
backup_and_link "$REPO_DIR/dictation/setup-dictation.sh" "$HOME/.local/bin/setup-dictation.sh"
info "first Super+Alt+L downloads the Parakeet model (~480 MB) into a uv venv"

# ── Neovim ─────────────────────────────────────────────────────
# config/nvim lives in THIS repo and is symlinked by the loop above, like every
# other config. It used to be cloned from cartermccann/dotfiles into
# ~/.cache/atlas/dotfiles-src and linked out of the cache, which made the editor
# the one part of atlas that wasn't in the repo -- you could not tell what nvim
# was running by reading this checkout, and `atlas-theme` had to write into a
# directory the installer did not own. Retired 2026-07-21.
step "neovim"
nvim_cache="$HOME/.cache/atlas/dotfiles-src"
if [ -d "$nvim_cache" ]; then
    info "stale nvim clone at ~/.cache/atlas/dotfiles-src — no longer used, safe to delete"
fi
info "lazy.nvim bootstraps plugins on first 'nvim' launch"
ok "config/nvim linked from the repo"

# ── Fish as login shell ────────────────────────────────────────
step "fish login shell"
if have fish; then
    current="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$current" != "$(command -v fish)" ]; then
        run_root chsh -s "$(command -v fish)" "$USER" && ok "login shell → fish" \
            || warn "could not chsh to fish (do it manually: chsh -s $(command -v fish))"
    else
        ok "already fish"
    fi
else
    warn "fish not installed — run the packages phase"
fi

ok "dotfiles phase complete"
