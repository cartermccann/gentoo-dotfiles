#!/usr/bin/env bash
# Phase: dotfiles — seed configs into ~/.config, set up shell.
#
# SEED, not deploy (contract flipped 2026-08-05): everything here copies into
# place only when the destination does not exist. On a fresh machine that is
# a full install; on a provisioned one it is a no-op. The live files are the
# source of truth — ./install.sh --harvest pulls them back into the repo.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

# ── Seed every config/<app> into ~/.config/<app> ───────────────
step "seed configs into ~/.config"
for dir in "$REPO_DIR"/config/*/; do
    name="$(basename "$dir")"
    seed_copy "${dir%/}" "$HOME/.config/$name"
done

# ── Hide junk entries from the launcher ────────────────────────
# NoDisplay stubs that shadow a system .desktop of the same name. XDG scans
# XDG_DATA_DIRS in order and ~/.local/share comes first, so these win without
# editing /usr -- a package update cannot revert them.
step "launcher: hide terminal apps and duplicates"
run mkdir -p "$HOME/.local/share/applications"
for f in "$REPO_DIR"/share/applications/*.desktop; do
    [ -e "$f" ] || continue
    seed_copy "$f" "$HOME/.local/share/applications/$(basename "$f")"
done
run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
ok "$(ls "$REPO_DIR"/share/applications/*.desktop 2>/dev/null | wc -l) entries hidden"

# ── Make mango scripts executable ──────────────────────────────
step "executable bits"
run chmod +x "$HOME"/.config/mango/autostart.sh "$HOME"/.config/mango/scripts/*.sh 2>/dev/null
ok "mango scripts executable"

# ── Dictation (Parakeet) scripts → ~/.local/bin ────────────────
step "dictation (Parakeet) scripts"
run mkdir -p "$HOME/.local/bin"
run chmod +x "$REPO_DIR"/dictation/*.sh
seed_copy "$REPO_DIR/dictation/toggle-dictation.sh" "$HOME/.local/bin/toggle-dictation.sh"
seed_copy "$REPO_DIR/dictation/setup-dictation.sh" "$HOME/.local/bin/setup-dictation.sh"

# ── Firmware setup (no boot-menu entry can do this — see the script) ─
seed_copy "$REPO_DIR/bin/atlas-firmware-setup" "$HOME/.local/bin/atlas-firmware-setup"
info "first Super+Alt+L downloads the Parakeet model (~480 MB) into a uv venv"

# ── Neovim ─────────────────────────────────────────────────────
# config/nvim is seeded by the loop above like every other config. It used to
# be cloned from cartermccann/dotfiles into ~/.cache/atlas/dotfiles-src —
# retired 2026-07-21. Live config at ~/.config/nvim is the editor's truth.
step "neovim"
info "lazy.nvim bootstraps plugins on first 'nvim' launch"
ok "config/nvim seeded from the repo"

# ── POSIX login-shell files ────────────────────────────────────
# ~/.profile and ~/.bash_profile are load-bearing: pam_openrc sources them at
# login to start OpenRC user services, so a hang in either is a hang at login.
# Seeded like everything else; installers appending PATH lines write to the
# live files, and --harvest carries them back when the seed earns a refresh.
step "login shell files"
seed_copy "$REPO_DIR/home/profile"      "$HOME/.profile"
seed_copy "$REPO_DIR/home/bash_profile" "$HOME/.bash_profile"
info "PATH lives in ~/.profile — keep it in sync with ~/.config/fish/config.fish"

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
