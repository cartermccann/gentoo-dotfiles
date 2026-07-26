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
    [apps]="25-apps.sh"
    [vendored]="27-vendored.sh"
    [ai]="30-ai-tools.sh"
    [devtools]="32-devtools.sh"
    [services]="35-services.sh"
    [dotfiles]="40-dotfiles.sh"
    [fonts]="45-fonts.sh"
    [theme]="50-theme.sh"
)
ORDER=(packages flatpaks apps vendored ai devtools services dotfiles fonts theme)

usage() {
    cat <<EOF
${C_BOLD}atlas-dotfiles installer${C_RESET}

Usage: ./install.sh [options] [phase ...]

Phases (run in this order if none given):
  packages   emerge desktop stack, CLI tools, langs, audio, bluetooth (needs doas)
  flatpaks   Zen, Spotify, Blanket via Flatpak (--user scope)
  apps       Obsidian, 1Password, Slack, OBS from portage (optional, needs doas)
  vendored   prebuilt apps nobody packages (Codex desktop) -> ~/apps
  ai         claude-code, codex, opencode, herdr + bun/deno/uv runtimes
  devtools   deploy/cloud/API CLIs from portage, npm, uv and upstream installers
  services   s6 user supervision tree for session daemons
  dotfiles   symlink configs into ~/.config (incl. nvim), deploy shell config
  theme      install the atlas-theme switcher and apply the default (cobalt)

Options:
  --dry-run   print what would happen, change nothing
  --check     diff the repo against the live system, change nothing
  --list      list phases and exit
  -h, --help  this help

Examples:
  ./install.sh                 # everything, in order
  ./install.sh dotfiles        # just deploy configs
  ./install.sh --dry-run       # preview the whole run
EOF
}

# ── --check: is the live system still what the repo says? ──────
# The Nix-ish property we want: the repo is the source of truth, and any
# drift is visible rather than silent.
run_check() {
    banner "atlas / config check" "repo vs live system"
    local drift=0

    step "system files (/etc)"
    while read -r src dst; do
        [ -z "$src" ] && continue
        if [ ! -d "$(dirname "$dst")" ]; then
            # e.g. /etc/ly before bin/setup-ly has been run.
            # Not drift — just not applicable on this machine yet.
            info "n/a      $dst (package not installed)"
        elif [ ! -f "$dst" ]; then
            err "MISSING  $dst"; drift=1
        elif cmp -s "$REPO_DIR/$src" "$dst"; then
            ok "in sync  $dst"
        else
            warn "DRIFTED  $dst"; drift=1
            diff -u "$dst" "$REPO_DIR/$src" | sed -n '3,12p' | sed 's/^/      /'
        fi
    done <<'MAP'
system/portage/package.accept_keywords/atlas /etc/portage/package.accept_keywords/atlas
system/portage/package.use/atlas /etc/portage/package.use/atlas
system/portage/package.license/atlas /etc/portage/package.license/atlas
system/ly/config.ini /etc/ly/config.ini
system/kernel/postinst.d/95-limine.install /etc/kernel/postinst.d/95-limine.install
system/conf.d/consolefont /etc/conf.d/consolefont
MAP

    step "user configs (~/.config -> repo)"
    for d in "$REPO_DIR"/config/*/; do
        local n dst; n=$(basename "$d"); dst="$HOME/.config/$n"
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$d")" ]; then
            ok "linked   ~/.config/$n"
        elif [ -e "$dst" ]; then
            warn "NOT A LINK  ~/.config/$n (local copy shadows the repo)"; drift=1
        else
            err "MISSING  ~/.config/$n"; drift=1
        fi
    done

    step "services"
    while read -r svc lvl; do
        case "$svc" in ""|\#*) continue ;; esac
        if ! [ -f "/etc/init.d/$svc" ]; then err "no init script: $svc"; drift=1
        elif rc-update show "$lvl" 2>/dev/null | grep -qw "$svc"; then ok "$svc -> $lvl"
        else warn "NOT ENABLED  $svc ($lvl)"; drift=1; fi
    done < "$REPO_DIR/system/services.conf"

    step "user services (s6)"
    local scan="$HOME/.local/state/s6/scan"
    if [ ! -d "$scan" ]; then
        info "n/a      no scan directory — './install.sh services' has not run"
    else
        # Whether a supervisor is alive has to be established FIRST, because
        # s6's control fifo outlives the supervisor that made it. Testing only
        # for the fifo reports "supervised" for a service that has not been
        # running since the last time a tree happened to be started — which is
        # exactly the silent failure this check exists to catch.
        local sup_up=0
        pgrep -u "$USER" -x s6-svscan >/dev/null 2>&1 && sup_up=1
        if [ "$sup_up" = "0" ]; then
            info "supervisor not running — it starts with the graphical session"
        fi
        for d in "$REPO_DIR"/services/*/; do
            [ -f "$d/run" ] || continue      # README.md is not a service
            local n dst; n=$(basename "${d%/}"); dst="$scan/$n"
            if [ ! -L "$dst" ]; then
                err "MISSING  $n (not linked into the scan directory)"; drift=1
            elif [ "$(readlink -f "$dst")" != "$(readlink -f "${d%/}")" ]; then
                warn "DRIFTED  $n (links somewhere other than the repo)"; drift=1
            elif [ "$sup_up" = "0" ]; then
                # Correct on disk, nothing supervising it. Not drift: outside a
                # session this is the expected state.
                info "linked   $n (defined, not running)"
            elif s6-svstat "$dst" 2>/dev/null | grep -q '^up'; then
                ok "up       $n  ($(s6-svstat "$dst" 2>/dev/null))"
            else
                warn "DOWN     $n  ($(s6-svstat "$dst" 2>&1 | head -1))"; drift=1
            fi
        done
    fi

    step "pending portage config"
    local cfgs; cfgs=$(find /etc/portage -name '._cfg*' 2>/dev/null | head)
    if [ -n "$cfgs" ]; then
        warn "unmerged ._cfg files — review before dispatch-conf, they can be STALE:"
        printf '      %s\n' $cfgs; drift=1
    else ok "no unmerged ._cfg files"; fi

    echo
    if [ "$drift" = "0" ]; then ok "system matches the repo"
    else warn "drift found — './install.sh packages' redeploys system files"; fi
    return 0
}

SELECTED=()
for arg in "$@"; do
    case "$arg" in
        --check) run_check; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        --list) printf '%s\n' "${ORDER[@]}"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        packages|flatpaks|apps|vendored|ai|devtools|services|dotfiles|fonts|theme) SELECTED+=("$arg") ;;
        *) err "unknown argument: $arg"; usage; exit 1 ;;
    esac
done
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=("${ORDER[@]}")

if [ "$(id -u)" -eq 0 ]; then
    err "run as your normal user (cjm), not root — the script uses $SUDO for root steps."
    exit 1
fi

banner "atlas / Gentoo + MangoWM" "cobalt-glass desktop setup"
[ "$DRY_RUN" = "1" ] && warn "DRY RUN — nothing will be changed"
info "phases: ${SELECTED[*]}"

keep_auth_warm            # prompt for doas once, then refresh in the background
trap stop_auth_warm EXIT

_i=0; _n=${#SELECTED[@]}
for name in "${SELECTED[@]}"; do
    _i=$((_i + 1))
    file="$REPO_DIR/phases/${PHASE_FILES[$name]}"
    if [ ! -f "$file" ]; then err "missing phase file: $file"; continue; fi
    phase_banner "$name" "$_i" "$_n"
    # shellcheck disable=SC1090
    bash "$file"
done

banner "done" "run bin/setup-ly, then reboot"
warn "ly is NOT installed by this script — it needs a Manifest workaround:"
warn "    doas bash bin/setup-ly      (see README for why)"
ok "Super+Space launcher · Super+Return ghostty · Super+Q close · Super+Shift+E exit"
info "theme: Super+Alt+T   ·   dictation: Super+Alt+L   ·   clipboard: Super+V"
