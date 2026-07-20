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
info "first Super+Ctrl+D downloads the Parakeet model (~480 MB) into a uv venv"

# ── Neovim (portable LazyVim config from your dotfiles repo) ───
step "neovim config"
nvim_cache="$HOME/.cache/atlas/dotfiles-src"
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] clone cartermccann/dotfiles, link config/nvim → ~/.config/nvim"
else
    if [ -d "$nvim_cache/.git" ]; then
        git -C "$nvim_cache" pull --ff-only >/dev/null 2>&1 || true
    else
        run mkdir -p "$(dirname "$nvim_cache")"
        git clone --depth 1 https://github.com/cartermccann/dotfiles "$nvim_cache" >/dev/null 2>&1 \
            || warn "could not clone dotfiles repo for nvim"
    fi
    if [ -d "$nvim_cache/config/nvim" ]; then
        backup_and_link "$nvim_cache/config/nvim" "$HOME/.config/nvim"
        info "lazy.nvim will bootstrap plugins on first 'nvim' launch"
    else
        warn "config/nvim not found in dotfiles clone — link it manually"
    fi
fi

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
