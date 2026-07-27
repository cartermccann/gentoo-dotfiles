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

# ── The system files this repo owns ────────────────────────────
# One list, two readers: the file-by-file diff below, and the stray scan that
# reports live files this repo has never heard of. Keeping it in one place is
# what stops a file being deployed but not checked, or checked but not deployed.
system_file_map() {
    cat <<'MAP'
system/portage/make.conf /etc/portage/make.conf
system/portage/package.accept_keywords/atlas /etc/portage/package.accept_keywords/atlas
system/portage/package.use/atlas /etc/portage/package.use/atlas
system/portage/package.license/atlas /etc/portage/package.license/atlas
system/portage/package.mask/atlas /etc/portage/package.mask/atlas
system/portage/repos.conf/eselect-repo.conf /etc/portage/repos.conf/eselect-repo.conf
system/portage/binrepos.conf/gentoo.conf /etc/portage/binrepos.conf/gentoo.conf
system/portage/bashrc /etc/portage/bashrc
system/ly/config.ini /etc/ly/config.ini
system/kernel/cmdline /etc/kernel/cmdline
system/kernel/postinst.d/95-limine.install /etc/kernel/postinst.d/95-limine.install
system/dracut.conf.d/atlas.conf /etc/dracut.conf.d/atlas.conf
system/btrbk/btrbk.conf /etc/btrbk/btrbk.conf
system/conf.d/consolefont /etc/conf.d/consolefont
MAP
}

# ── Atoms this repo declares ───────────────────────────────────
# Read from two places, because the phases install packages two ways: the
# CORE/TOOLS/APPS arrays, and the handful of bootstrap `emerge` calls that run
# before those arrays (git and eselect-repository, needed to enable GURU).
#
# Only text INSIDE a NAME=( ... ) block counts, with comments stripped. A
# category/name string in prose is not a declaration — 45-fonts.sh mentions
# "media-fonts/geist, absent" and 30-ai-tools.sh mentions
# "dev-lang/zig-bin-0.15.2" in comments, and a naive grep reads both as
# packages this repo installs.
declared_atoms() {
    local f
    # bin/setup-* counts too: setup-ly and setup-limine emerge x11-misc/ly and
    # sys-boot/limine, which the phases deliberately do not (ly needs a GURU
    # Manifest workaround, so it is an explicit auditable step).
    #
    # Only setup-*, not all of bin/. The other scripts there are tools, not
    # installers, and scanning them read package names out of help text: a
    # cleanup script printing "emerge --noreplace dev-qt/qtbase" as a recovery
    # hint was enough to make the world diff believe the repo installs qtbase.
    for f in "$REPO_DIR"/phases/*.sh "$REPO_DIR"/bin/setup-*; do
        [ -f "$f" ] || continue
        awk '
            /^[A-Z][A-Z_]*=\(/ { inarr=1; next }
            inarr && /^\)/     { inarr=0; next }
            inarr              { sub(/#.*/, ""); print }
        ' "$f"
        # An emerge that REMOVES something is not a declaration. Without this,
        # `emerge --deselect dev-qt/qtbase` in a cleanup script read as "the repo
        # installs qtbase" and quietly satisfied the world diff — the opposite of
        # the truth.
        grep -E '\bemerge\b' "$f" \
            | grep -vE -- '--deselect|--unmerge|--depclean|[[:space:]]-C[[:space:]]' \
            | sed 's/#.*//'
    done | tr ' \t' '\n\n' \
        | sed 's/[;&|()"'"'"'`]//g' \
        | grep -oE '^[<>=~]*[a-z][a-z0-9]*(-[a-z0-9]+)?/[a-zA-Z0-9][a-zA-Z0-9._+-]*$' \
        | sed 's/^[<>=~]*//' \
        | sed -E 's/-[0-9][a-zA-Z0-9._-]*$//' \
        | valid_categories_only \
        | sort -u
}

# A path is not an atom. `services/micro-herdr` matches the shape of a package
# perfectly, so shape alone is not enough — the category has to be a real one.
# profiles/categories is portage's own authoritative list.
valid_categories_only() {
    local cats="/var/db/repos/gentoo/profiles/categories"
    if [ -r "$cats" ]; then
        grep -F -f <(sed 's|$|/|' "$cats") -
    else
        cat    # no tree to validate against; better to over-report than to hide
    fi
}

world_atoms() {
    # Strip slot (:3.13) and repo (::guru) suffixes, drop @set lines.
    sed 's/#.*//; s/::.*//; s/:.*//; /^@/d; /^[[:space:]]*$/d' \
        /var/lib/portage/world | sort -u
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
        if [ ! -f "$REPO_DIR/$src" ]; then
            # The map names a file the repo does not have. Distinct from DRIFTED:
            # nothing differs, the source of truth is simply absent, and `diff`
            # would just print "No such file or directory".
            err "NO REPO FILE  $src (mapped to $dst, but not in the repo)"; drift=1
        elif [ ! -d "$(dirname "$dst")" ]; then
            # e.g. /etc/ly before bin/setup-ly has been run.
            # Not drift — just not applicable on this machine yet.
            info "n/a      $dst (parent directory absent)"
        elif [ ! -f "$dst" ]; then
            err "MISSING  $dst"; drift=1
        elif cmp -s "$REPO_DIR/$src" "$dst"; then
            ok "in sync  $dst"
        else
            warn "DRIFTED  $dst"; drift=1
            diff -u "$dst" "$REPO_DIR/$src" | sed -n '3,12p' | sed 's/^/      /'
        fi
    done < <(system_file_map)

    step "system files: is anything deploying them?"
    # "in sync" only means the live file matches the repo. It does NOT mean any
    # phase would ever put it there. /etc/conf.d/consolefont sat in the map for
    # weeks reading "in sync" while no phase deployed it — it had been placed by
    # hand once, so a clean checkout would have silently dropped it. A mapped
    # file that nothing installs is a lie the check was telling.
    local orphan=0
    while read -r src dst; do
        [ -z "$src" ] && continue
        if grep -rqF "$src" "$REPO_DIR"/phases/ "$REPO_DIR"/bin/ 2>/dev/null; then
            continue
        fi
        err "NOT DEPLOYED  $src is checked but no phase or bin/ script installs it"
        orphan=1; drift=1
    done < <(system_file_map)
    [ "$orphan" = "0" ] && ok "every mapped system file has something that deploys it"

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
                # s6 measures uptime from the timestamp it recorded when the
                # service started, so a clock STEP after that point corrupts the
                # figure. On 2026-07-26 both services reported ~31,768,515
                # seconds (367 days) on a machine that had been up 18 minutes:
                # the RTC read 2025-07-24 at boot, s6 stamped against that, then
                # chronyd stepped the clock forward a year.
                #
                # A service cannot have been running longer than the machine has
                # been up, so /proc/uptime is the ceiling. Reporting "unknown" is
                # the point of this: the number exists to distinguish "up since
                # login" from "restarted an hour ago", and a wrong number answers
                # that question confidently and incorrectly.
                local svstat sv_secs sys_secs
                svstat=$(s6-svstat "$dst" 2>/dev/null)
                sv_secs=$(printf '%s' "$svstat" | grep -oE '[0-9]+ seconds' | grep -oE '^[0-9]+')
                sys_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
                if [ -n "$sv_secs" ] && [ -n "$sys_secs" ] && [ "$sv_secs" -gt "$sys_secs" ]; then
                    ok "up       $n  (age unknown — start time predates boot, clock stepped after s6 started)"
                else
                    ok "up       $n  ($svstat)"
                fi
            else
                warn "DOWN     $n  ($(s6-svstat "$dst" 2>&1 | head -1))"; drift=1
            fi
        done
    fi

    step "undeclared portage config"
    # The file-by-file comparison above only sees files this repo already knows
    # about, so anything ELSE under /etc/portage is invisible to it — including
    # what portage's own --autounmask-write drops there mid-emerge.
    #
    # Four such files were found under package.* on 2026-07-26 (zz-autounmask,
    # system, webkit-gtk, zen-bin), all load-bearing. Then three MORE turned up
    # at the top level, which this scan originally did not reach at all:
    # make.conf (MAKEOPTS, march, FEATURES=getbinpkg), repos.conf (the GURU
    # overlay URI, without which swaync and sd do not exist) and binrepos.conf
    # (the x86-64-v3 binhost — without it this is a from-source machine). A
    # clean checkout reproduced none of them. Listing strays is how that stops
    # being a once-a-year discovery.
    local stray=0 f known
    known=$(system_file_map | awk '{print $2}')
    while read -r f; do
        [ -n "$f" ] || continue
        # Files the repo deploys are diffed above, not reported here.
        printf '%s\n' "$known" | grep -qxF "$f" && continue
        case "$(basename "$f")" in
            # The installer's own displaced copies. They live in
            # CONFIG_BACKUP_DIR now (see lib/common.sh), but old ones linger.
            *.bak.*)
                warn "STALE BACKUP  $f — safe to delete"; stray=1; drift=1; continue ;;
            *autounmask*)
                warn "AUTOUNMASK  $f — portage wrote this during an emerge"
                info "      fold the entries into system/portage/ and delete it"
                stray=1; drift=1; continue ;;
        esac
        warn "UNDECLARED  $f (not owned by the repo)"
        stray=1; drift=1
    done < <({ find /etc/portage/package.use /etc/portage/package.accept_keywords \
                    /etc/portage/package.license /etc/portage/package.mask \
                    -maxdepth 1 -type f 2>/dev/null
               # Top-level and the directories portage reads wholesale. Excludes
               # gnupg/ (binpkg keyring, portage's own state) and make.profile
               # (an eselect-managed symlink, not a config file).
               find /etc/portage -maxdepth 1 -type f 2>/dev/null
               find /etc/portage/repos.conf /etc/portage/binrepos.conf \
                    /etc/portage/env /etc/portage/sets /etc/portage/savedconfig \
                    -type f 2>/dev/null
             } | sort -u)
    [ "$stray" = "0" ] && ok "every /etc/portage file is repo-owned"

    step "packages (@world vs declared)"
    # `emerge --noreplace` adds to @world, so anything installed by hand at a
    # shell is indistinguishable from something a phase installed — until you
    # rebuild on bare metal and it is simply absent. On 2026-07-26 this found 28
    # such packages, including app-admin/doas (the tool install.sh runs on),
    # sys-kernel/gentoo-kernel-bin (the kernel), and dev-util/github-cli (the
    # credential helper in ~/.gitconfig).
    local undeclared_pkgs missing_pkgs
    undeclared_pkgs=$(comm -13 <(declared_atoms) <(world_atoms))
    missing_pkgs=$(comm -23 <(declared_atoms) <(world_atoms))
    if [ -n "$undeclared_pkgs" ]; then
        warn "$(printf '%s\n' "$undeclared_pkgs" | wc -l) in @world, declared in no phase:"
        printf '      %s\n' $undeclared_pkgs; drift=1
    else
        ok "every @world package is declared in a phase"
    fi
    if [ -n "$missing_pkgs" ]; then
        # Either a typo'd atom, or a package the repo asks for that never
        # installed. Both are worth seeing; neither is visible any other way.
        warn "declared but not in @world (typo, or never installed):"
        printf '      %s\n' $missing_pkgs; drift=1
    fi

    step "services (enabled vs declared)"
    # The loop above asks "is what the repo declares enabled?" — the opposite
    # question, "is anything else enabled?", went unasked. docker, sshd, chronyd
    # and sysklogd were all live and undeclared on 2026-07-26.
    #
    # BASELINE is the stage3 + profile set: services OpenRC brings up on its own,
    # which this repo neither enables nor should have to declare. Anything in
    # boot/default that is neither baseline nor declared is drift.
    local BASELINE="binfmt bootmisc fsck hostname hwclock keymaps local
        localmount loopback modules mtab netmount procfs root save-keymaps
        save-termencoding seedrng swap sysctl systemd-tmpfiles-setup
        termencoding"
    local declared_svcs extra_svcs=""
    declared_svcs=$(sed 's/#.*//' "$REPO_DIR/system/services.conf" | awk '{print $1}')
    for lvl in boot default; do
        while read -r svc; do
            [ -n "$svc" ] || continue
            printf '%s\n' $BASELINE | grep -qxF "$svc" && continue
            printf '%s\n' $declared_svcs | grep -qxF "$svc" && continue
            extra_svcs="$extra_svcs $svc($lvl)"
        done < <(rc-update show "$lvl" 2>/dev/null | awk '{print $1}')
    done
    if [ -n "$extra_svcs" ]; then
        warn "enabled but declared nowhere:$extra_svcs"
        info "      add to system/services.conf with the reason, or disable"
        drift=1
    else
        ok "no undeclared services enabled"
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
