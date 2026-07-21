#!/usr/bin/env bash
# Shared helpers for the gentoo-dotfiles installer.

# ── Palette (16-color — safe in the bare Linux console) ────────
if [ -t 1 ]; then
    C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
    C_BLUE=$'\e[94m'; C_GREEN=$'\e[92m'; C_YELLOW=$'\e[93m'
    C_RED=$'\e[91m'; C_CYAN=$'\e[96m'; C_GREY=$'\e[90m'
else
    C_RESET=; C_BOLD=; C_DIM=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=; C_CYAN=; C_GREY=
fi
BOX_W=52

_rule() { printf '─%.0s' $(seq "${1:-$BOX_W}"); }

banner() {   # title [subtitle]
    local t="$1" s="${2:-}" pad
    printf '\n%s%s╭%s╮%s\n' "$C_BLUE" "$C_BOLD" "$(_rule)" "$C_RESET"
    printf -v pad '%-*s' "$BOX_W" "  $t"
    printf '%s%s│%s%s%s%s%s│%s\n' "$C_BLUE" "$C_BOLD" "$C_RESET" "$C_BOLD" "$pad" "$C_RESET" "$C_BLUE$C_BOLD" "$C_RESET"
    if [ -n "$s" ]; then
        printf -v pad '%-*s' "$BOX_W" "  $s"
        printf '%s%s│%s%s%s%s%s│%s\n' "$C_BLUE" "$C_BOLD" "$C_RESET" "$C_DIM" "$pad" "$C_RESET" "$C_BLUE$C_BOLD" "$C_RESET"
    fi
    printf '%s%s╰%s╯%s\n' "$C_BLUE" "$C_BOLD" "$(_rule)" "$C_RESET"
}

phase_banner() {  # name num total
    printf '\n%s%s▶ %s%s  %sphase %s/%s%s\n' "$C_BLUE" "$C_BOLD" "$1" "$C_RESET" "$C_GREY" "$2" "$3" "$C_RESET"
    printf '%s%s%s\n' "$C_GREY" "$(_rule)" "$C_RESET"
}

progress() {  # current total label
    local cur=$1 tot=$2 label=${3:-} w=22 filled bar empty
    [ "$tot" -gt 0 ] || tot=1
    filled=$(( cur * w / tot )); [ "$filled" -gt "$w" ] && filled=$w
    printf -v bar '%*s' "$filled" ''; bar=${bar// /█}
    printf -v empty '%*s' "$((w-filled))" ''; empty=${empty// /░}
    printf '\r  %s%s%s%s%s %s%d/%d%s %s%-22.22s%s' \
        "$C_GREEN" "$bar" "$C_GREY" "$empty" "$C_RESET" \
        "$C_BOLD" "$cur" "$tot" "$C_RESET" "$C_DIM" "$label" "$C_RESET"
}

step() { printf '\n%s▸ %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info() { printf '  %s%s%s\n' "$C_GREY" "$*" "$C_RESET"; }
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

# ── Keep doas/sudo warm: prompt once, refresh in the background ─
KEEPALIVE_PID=""
keep_auth_warm() {
    [ -n "$SUDO" ] || return 0
    [ "$(id -u)" -eq 0 ] && return 0
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    as_root true || return 1
    ( while true; do sleep 50; $SUDO -n true 2>/dev/null || break; done ) &
    KEEPALIVE_PID=$!
}
stop_auth_warm() { [ -n "$KEEPALIVE_PID" ] && kill "$KEEPALIVE_PID" 2>/dev/null || true; }
