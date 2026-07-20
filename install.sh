#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  atlas-dotfiles installer
#  Surface Laptop Studio · Gentoo · MangoWM
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

export DRY_RUN=0

# phase short-name → script
declare -A PHASE_FILES=(
    [packages]="10-packages.sh"
    [flatpaks]="20-flatpaks.sh"
    [ai]="30-ai-tools.sh"
    [dotfiles]="40-dotfiles.sh"
    [theme]="50-theme.sh"
)
ORDER=(packages flatpaks ai dotfiles theme)

usage() {
    cat <<EOF
${C_BOLD}atlas-dotfiles installer${C_RESET}

Usage: ./install.sh [options] [phase ...]

Phases (run in this order if none given):
  packages   emerge desktop stack, CLI tools, langs, audio, bluetooth (needs doas)
  flatpaks   Zen, Spotify, Beeper, Blanket, (Helium) via Flatpak
  ai         claude-code, codex, opencode, herdr + bun/deno/uv runtimes
  dotfiles   symlink configs into ~/.config, clone nvim, deploy shell config
  theme      install the atlas-theme switcher and apply the default (cobalt)

Options:
  --dry-run   print what would happen, change nothing
  --list      list phases and exit
  -h, --help  this help

Examples:
  ./install.sh                 # everything, in order
  ./install.sh dotfiles        # just deploy configs
  ./install.sh --dry-run       # preview the whole run
EOF
}

SELECTED=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --list) printf '%s\n' "${ORDER[@]}"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        packages|flatpaks|ai|dotfiles|theme) SELECTED+=("$arg") ;;
        *) err "unknown argument: $arg"; usage; exit 1 ;;
    esac
done
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=("${ORDER[@]}")

if [ "$(id -u)" -eq 0 ]; then
    err "run as your normal user (cjm), not root — the script uses $SUDO for root steps."
    exit 1
fi

printf '%s╔══════════════════════════════════════╗%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
printf '%s║   atlas · Gentoo + MangoWM setup     ║%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
printf '%s╚══════════════════════════════════════╝%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
[ "$DRY_RUN" = "1" ] && warn "DRY RUN — nothing will be changed"
info "phases: ${SELECTED[*]}"

for name in "${SELECTED[@]}"; do
    file="$REPO_DIR/phases/${PHASE_FILES[$name]}"
    if [ ! -f "$file" ]; then err "missing phase file: $file"; continue; fi
    step "phase: $name"
    # shellcheck disable=SC1090
    bash "$file"
done

step "done"
ok "Reboot when ready. ly will greet you — pick the Mango session and log in."
info "First-time keys:  Super+D launcher · Super+Return ghostty · Super+Q close · Super+Shift+Q exit"
