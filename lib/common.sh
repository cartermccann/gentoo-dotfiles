#!/usr/bin/env bash
# Shared helpers for the atlas-dotfiles installer.

# ── Colors / logging ───────────────────────────────────────────
if [ -t 1 ]; then
    C_RESET=$'\e[0m'; C_BLUE=$'\e[34m'; C_GREEN=$'\e[32m'
    C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_BOLD=$'\e[1m'
else
    C_RESET=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=; C_BOLD=
fi

step() { printf '\n%s▸ %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── Privilege escalation (doas preferred, sudo fallback) ───────
if have doas; then SUDO=doas
elif have sudo; then SUDO=sudo
else SUDO=""; fi

as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif [ -n "$SUDO" ]; then $SUDO "$@"
    else err "need root for: $*"; return 1; fi
}

# ── DRY_RUN wrapper ────────────────────────────────────────────
run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '  %s[dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
    else
        "$@"
    fi
}

run_root() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '  %s[dry-run]%s (root) %s\n' "$C_YELLOW" "$C_RESET" "$*"
    else
        as_root "$@"
    fi
}

# ── Symlink a path into place, backing up whatever is there ────
backup_and_link() {
    local src=$1 dst=$2
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        ok "linked: ${dst/#$HOME/\~} (already)"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        run mv "$dst" "$dst.bak.$(date +%Y%m%d-%H%M%S)"
        warn "backed up existing ${dst/#$HOME/\~}"
    fi
    run mkdir -p "$(dirname "$dst")"
    run ln -sfn "$src" "$dst"
    ok "linked: ${dst/#$HOME/\~}"
}
