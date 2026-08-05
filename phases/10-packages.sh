#!/usr/bin/env bash
# Phase: packages — Gentoo tree (binhost) + GURU overlay.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

# ── Portage config: keywords + USE ─────────────────────────────
step "portage config (keywords + USE + licenses)"
run_root mkdir -p /etc/portage/package.accept_keywords /etc/portage/package.use \
                  /etc/portage/package.license /etc/portage/package.mask

# Source of truth is system/portage/ in this repo — real files you can read,
# diff and edit. deploy_system_file (lib/common.sh) copies and reports drift
# rather than symlinking: /etc/portage decides what root emerges, so pointing
# it at a user-writable git checkout would be a privilege-escalation path.

deploy_system_file "$REPO_DIR/system/portage/package.accept_keywords/atlas" \
                   /etc/portage/package.accept_keywords/atlas
deploy_system_file "$REPO_DIR/system/portage/package.use/atlas" \
                   /etc/portage/package.use/atlas
deploy_system_file "$REPO_DIR/system/portage/package.license/atlas" \
                   /etc/portage/package.license/atlas
deploy_system_file "$REPO_DIR/system/portage/package.mask/atlas" \
                   /etc/portage/package.mask/atlas

# package.env + env/: per-package INSTALL_MASK so gui-wm/mangowm stops
# reinstalling a session .desktop that this repo owns. These must land BEFORE
# any emerge below, or the very next mangowm merge reverts it again.
deploy_system_file "$REPO_DIR/system/portage/package.env/atlas" \
                   /etc/portage/package.env/atlas
deploy_system_file "$REPO_DIR/system/portage/env/no-session-desktop.conf" \
                   /etc/portage/env/no-session-desktop.conf

# The three files below decide HOW everything above builds, and none of them was
# tracked until 2026-07-26 — a clean checkout got stage3 defaults (-j1, no
# binhost, no GURU) and nothing reported it. Order matters: make.conf and the
# binhost have to be in place before the first emerge, and repos.conf before the
# GURU step below.
deploy_system_file "$REPO_DIR/system/portage/make.conf" \
                   /etc/portage/make.conf
deploy_system_file "$REPO_DIR/system/portage/repos.conf/eselect-repo.conf" \
                   /etc/portage/repos.conf/eselect-repo.conf
deploy_system_file "$REPO_DIR/system/portage/binrepos.conf/gentoo.conf" \
                   /etc/portage/binrepos.conf/gentoo.conf

# Boot and initramfs inputs. /etc/kernel/cmdline is what 95-limine.install reads
# to build every Limine entry — see system/kernel/README.md, and note that it
# must never contain comments. dracut.conf.d/atlas.conf carries no active
# settings yet; it exists so the file has an owner before encryption needs it.
deploy_system_file "$REPO_DIR/system/kernel/cmdline" \
                   /etc/kernel/cmdline
deploy_system_file "$REPO_DIR/system/dracut.conf.d/atlas.conf" \
                   /etc/dracut.conf.d/atlas.conf

# Snapshot policy. /.snapshots has been mounted since the install with nothing
# writing to it; this is what finally uses it. bashrc is the trigger: it
# snapshots before portage installs anything, which is the whole scheduling
# story here — btrbk's own timer is a systemd unit and this machine is OpenRC.
deploy_system_file "$REPO_DIR/system/btrbk/btrbk.conf" \
                   /etc/btrbk/btrbk.conf
deploy_system_file "$REPO_DIR/system/portage/bashrc" \
                   /etc/portage/bashrc

# consolefont was in --check's file map but NO phase deployed it: it read
# "in sync" only because it had been placed by hand once. On a clean checkout the
# ly greeter would have silently fallen back to the 8x16 console font. Found
# 2026-07-26 by checking the map for entries nothing installs.
deploy_system_file "$REPO_DIR/system/conf.d/consolefont" \
                   /etc/conf.d/consolefont

# Device access for the Work Louder boards — the Input configurator in
# ~/apps/input and the micro-herdr service both need it. Written here rather
# than by upstream's generator script, which hands every match MODE="0666";
# the file itself explains the rest. Rules are read live, so this needs
#   doas udevadm control --reload && doas udevadm trigger
# to take effect on already-attached devices, and a BLE device must be
# reconnected rather than merely re-triggered.
deploy_system_file "$REPO_DIR/system/udev/99-worklouder.rules" \
                   /etc/udev/rules.d/99-worklouder.rules

# ── Package sets ───────────────────────────────────────────────
# These four files are the source of truth for every portage package this repo
# installs; the phases below read them rather than carrying bash arrays. They
# must be in /etc/portage/sets BEFORE any `emerge @atlas-*` below, or emerge
# resolves the set against a stale copy. See docs/LAYOUT.md.
#
# atlas-bootstrap is the one that is easy to miss: git, eselect-repository,
# flatpak and ly are emerged inline (here and in 20-flatpaks / bin/setup-ly),
# never from an array, so nothing declared them until the move to package sets. Once the world
# file is emptied they would be the first things `emerge --depclean` removes.
step "package sets"
deploy_set atlas-bootstrap
deploy_set atlas-core
deploy_set atlas-tools
deploy_set atlas-apps
deploy_set atlas-devtools

# ── GURU overlay ───────────────────────────────────────────────
step "GURU overlay"
if have git; then :; else run_root emerge --noreplace --quiet dev-vcs/git; fi
if eselect repository list -i 2>/dev/null | grep -qw guru; then
    ok "guru already enabled"
else
    run_root emerge --noreplace --quiet app-eselect/eselect-repository
    run_root eselect repository enable guru
fi
run_root emerge --sync guru

# ── Core desktop + system packages (one transaction) ───────────
# The atom list lives in system/portage/sets/atlas-core, NOT here. It used to
# be an 80-line bash array; the move to package sets took it out so that `emerge --depclean`
# can treat it as the set of things that are supposed to exist. Deleting a line
# from the set file is now a removal, which a bash array could never express.
step "core packages (desktop stack, audio, bluetooth, langs)"
LOG="$HOME/.cache/atlas-emerge.log"; mkdir -p "$(dirname "$LOG")"; : > "$LOG"

mapfile -t CORE < <(read_set atlas-core)
mapfile -t TOOLS < <(read_set atlas-tools)
[ ${#CORE[@]} -gt 0 ] || { err "atlas-core set is empty — refusing to continue"; exit 1; }

# Try a qualified atom, then fall back to the bare name (covers a wrong
# category guess); autounmask accepts ~amd64/USE; everything logged.
#
# --oneshot, not --noreplace: this is the per-atom FALLBACK path, and the batch
# emerge below is what registers @atlas-core in world_sets. If this path wrote
# to the world file too, every atom would become an individual depclean root
# and the set would stop being the source of truth — which is the exact drift
# package sets exist to remove.
emerge_pkg() {
    local atom="$1" bare="${1##*/}"
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] emerge $atom"; return 0; }
    echo "### $atom" >> "$LOG"
    as_root emerge --oneshot --quiet --autounmask --autounmask-continue "$atom" >>"$LOG" 2>&1 && return 0
    [ "$bare" = "$atom" ] && return 1
    echo "### retry bare: $bare" >> "$LOG"
    as_root emerge --oneshot --quiet --autounmask --autounmask-continue "$bare" >>"$LOG" 2>&1
}

# @atlas-bootstrap first: git, eselect-repository, flatpak and ly are already
# installed by the inline emerges above and in other phases, so this installs
# nothing. What it does is register the set as a depclean root, which is the
# only thing standing between a converged run and an uninstalled bootloader.
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] emerge --noreplace @atlas-bootstrap"
else
    as_root emerge --noreplace --quiet @atlas-bootstrap >>"$LOG" 2>&1 \
        && ok "@atlas-bootstrap registered" \
        || warn "@atlas-bootstrap did not register (see $LOG)"
fi

# CORE as one set transaction; if it fails, install individually so one bad
# atom can't block the rest of the desktop. The batch is what registers
# @atlas-core in world_sets, so it is tried even when everything is present.
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] emerge @atlas-core (${#CORE[@]} packages)"
elif ! as_root emerge --verbose --noreplace --autounmask --autounmask-write --autounmask-continue @atlas-core; then
    warn "core batch had issues — installing core packages individually"
    core_missed=()
    for pkg in "${CORE[@]}"; do
        emerge_pkg "$pkg" && ok "$pkg" || { core_missed+=("$pkg"); warn "skipped '$pkg'"; }
    done
    if [ ${#core_missed[@]} -gt 0 ]; then
        warn "core unresolved: ${core_missed[*]} (see $LOG)"
        # The batch failed, so the set never registered and its atoms are not
        # depclean roots. Saying so matters: --check will report them all as
        # removable and the cause will not be obvious.
        warn "  @atlas-core is NOT registered — fix the above, then re-run this phase"
    fi
fi

# ── CLI tools (resilient: try each, report misses) ─────────────
# Atom list: system/portage/sets/atlas-tools.
step "CLI tools (from your kronos toolset)"
missed=(); _ti=0; _tn=${#TOOLS[@]}
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] emerge @atlas-tools ($_tn packages)"
elif as_root emerge --noreplace --quiet --autounmask --autounmask-continue @atlas-tools >>"$LOG" 2>&1; then
    ok "@atlas-tools registered ($_tn packages)"
else
    # Same fallback shape as CORE: one unresolvable tool must not cost the
    # other thirty. Note these land via --oneshot, so a tool installed by this
    # path is NOT a depclean root until the set emerge above succeeds.
    warn "tools batch had issues — installing individually"
    for pkg in "${TOOLS[@]}"; do
        _ti=$((_ti + 1))
        progress "$_ti" "$_tn" "${pkg##*/}"
        emerge_pkg "$pkg" || missed+=("$pkg")
    done
    progress "$_tn" "$_tn" "done"; printf '\n'
    ok "$(( _tn - ${#missed[@]} ))/$_tn tools installed"
    if [ ${#missed[@]} -gt 0 ]; then
        warn "unresolved: ${missed[*]}"
        warn "  reasons: $LOG   ·   find the right atom with:  emerge -s <name>"
        warn "  if keyword/USE changes were written: doas dispatch-conf && ./install.sh packages"
    fi
fi

# ── gum: not packaged in ::gentoo or ::guru — install via go ───
step "gum (via go install — no ebuild exists)"
if have gum; then
    ok "gum already installed"
elif [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] go install github.com/charmbracelet/gum@latest"
elif have go; then
    if go install github.com/charmbracelet/gum@latest >>"$LOG" 2>&1; then
        ok "gum -> $(go env GOBIN 2>/dev/null || echo "$HOME/go/bin")"
    else
        warn "gum install failed (see $LOG)"
    fi
else
    warn "go not available — skipping gum"
fi

# ── Wayland session entry (tuigreet reads this dir) ────────────
step "mango wayland session"
if [ "$DRY_RUN" != "1" ]; then
    as_root install -D -m 0755 "$REPO_DIR/system/bin/mango-session" /usr/local/bin/mango-session
    ok "/usr/local/bin/mango-session"
fi
# The session entry is a TRACKED file, not a heredoc, since 2026-08-05.
#
# It used to be written inline here with the comment "Always rewrite: the Exec
# line changed once already". Rewriting was the right instinct and still not
# enough: a phase only rewrites when the phase is RUN, and nothing runs it after
# an emerge. Upgrading mangowm 0.15.2 -> 0.15.6 reinstalled the package's copy
# (Exec=mango), Ly launched mango without the wrapper, and the session came up
# with no D-Bus session bus -- waybar, swaync, nm-applet, blueman-applet and
# swayidle all silently down, swaybg and wlsunset fine. --check could not see
# any of it, because a file generated by a heredoc is in no map.
#
# Tracked, it is in system_file_map: --check diffs it and reports drift. And
# system/portage/env/no-session-desktop.conf INSTALL_MASKs the path for
# gui-wm/mangowm so portage stops installing the competing copy at all.
deploy_system_file "$REPO_DIR/system/wayland-sessions/mango.desktop" \
                   /usr/share/wayland-sessions/mango.desktop 0644

# ── ly: config ─────────────────────────────────────────────────
# ly itself is installed by bin/setup-ly (GURU Manifest workaround); this only
# deploys its config when the binary is present.
step "ly (login manager)"
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would install /etc/ly/config.ini"
elif have ly; then
    deploy_system_file "$REPO_DIR/system/ly/config.ini" /etc/ly/config.ini 0644
else
    warn "ly not installed — run:  doas bash bin/setup-ly"
fi

# ── Services ───────────────────────────────────────────────────
step "enable services"
# Guard on the init script existing — `rc-update add` on a package that failed
# to emerge fails silently here and you only find out at boot (this is exactly
# how atlas ended up with no display manager on the first run).
svc_missing=()
add_svc() {  # name runlevel
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] rc-update add $1 $2"; return; fi
    if [ ! -f "/etc/init.d/$1" ]; then
        svc_missing+=("$1"); warn "no init script for '$1' — package not installed?"
        return
    fi
    as_root rc-update add "$1" "$2" >/dev/null 2>&1 && ok "$1 -> $2" || warn "could not enable $1"
}
while read -r _svc _lvl; do
    case "$_svc" in ""|\#*) continue ;; esac
    add_svc "$_svc" "$_lvl"
done < "$REPO_DIR/system/services.conf"
if [ ${#svc_missing[@]} -gt 0 ]; then
    warn "services NOT enabled (missing packages): ${svc_missing[*]}"
    warn "  install them, then re-run: ./install.sh packages"
fi
warn "ly owns tty2 at boot — bin/setup-ly disables the competing getty."

ok "packages phase complete"
