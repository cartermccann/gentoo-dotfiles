#!/usr/bin/env bash
# Phase: apps — GUI applications that ARE packaged for Gentoo.
#
# Separate from 10-packages (the desktop stack + CLI, which the machine needs
# to boot into a usable session) and from 20-flatpaks (GUI apps Gentoo does
# NOT package). This is the middle case: desktop software with a real ebuild,
# all of it optional, none of it load-bearing. Run it or don't — nothing else
# in the repo depends on anything here.
#
# The atom list is system/portage/sets/atlas-apps, not an array here — see
# docs/LAYOUT.md. That file carries the per-package notes (which ones are
# proprietary repacks needing a keyword line, and why obs-studio and
# easyeffects are USE-flag sensitive).
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

LOG="$HOME/.cache/atlas-emerge.log"; mkdir -p "$(dirname "$LOG")"

# Deploy before emerging @atlas-apps: this phase is runnable on its own
# (`./install.sh apps`), so it cannot assume the packages phase put a current
# copy in /etc/portage/sets.
step "app set"
deploy_set atlas-apps
mapfile -t APPS < <(read_set atlas-apps)

# --oneshot on the per-atom path. The set emerge below is what registers
# @atlas-apps in world_sets; if this wrote to the world file as well, each app
# would become its own depclean root and removing a line from the set file
# would stop meaning anything. See docs/LAYOUT.md.
emerge_app() {
    local atom="$1"
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] emerge $atom"; return 0; }
    echo "### $atom" >> "$LOG"
    as_root emerge --oneshot --quiet --autounmask --autounmask-continue "$atom" \
        >>"$LOG" 2>&1
}

# Try the set as one transaction first — that is what registers it. Fall back
# to the per-atom loop only when it fails, because these are optional apps and
# one unavailable repack must not cost the other six. The loop is also the only
# path that can say *which* atom failed.
step "desktop applications"
_n=${#APPS[@]}
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] emerge @atlas-apps ($_n packages)"
elif as_root emerge --noreplace --quiet --autounmask --autounmask-continue @atlas-apps \
        >>"$LOG" 2>&1; then
    ok "@atlas-apps registered ($_n packages)"
else
    warn "app set had issues — installing individually"
    missed=(); _i=0
    for pkg in "${APPS[@]}"; do
        _i=$((_i + 1))
        progress "$_i" "$_n" "${pkg##*/}"
        emerge_app "$pkg" || missed+=("$pkg")
    done
    progress "$_n" "$_n" "done"; printf '\n'
    ok "$(( _n - ${#missed[@]} ))/$_n apps installed"
    if [ ${#missed[@]} -gt 0 ]; then
        warn "unresolved: ${missed[*]}"
        warn "  reasons: $LOG"
        warn "  if keyword/USE changes were written: doas dispatch-conf && ./install.sh apps"
        warn "  @atlas-apps is NOT registered while any atom fails to resolve"
    fi
fi

# ── 1Password: the parts emerge cannot do ──────────────────────
step "1Password notes"
# The ebuild renders its polkit action file from /etc/passwd at BUILD time,
# baking in whichever uid-4-digit users existed then. That is fine for cjm
# (uid 1000) but means a user added later gets no policy until 1password is
# re-emerged. Worth knowing before you debug "unlock fails for the new user".
if have pkaction; then
    ok "polkit present — system-auth unlock will work"
else
    warn "polkit not installed — 1Password cannot use system authentication"
fi
# Browser integration talks over a native-messaging socket that 1Password
# gates on a signed browser binary. Flatpak Zen is sandboxed and unsigned as
# far as 1Password is concerned, so the extension will not pair with it.
info "browser unlock: flatpak Zen will not pair (sandboxed + unrecognised binary)"
info "  add non-standard browsers to /etc/1password/custom_allowed_browsers, one per line"

# ── OBS: confirm the capture path actually got built ───────────
# USE=pipewire is the whole reason OBS is usable on wlroots — without it there
# is no screen capture at all, only a webcam. A silently-dropped USE flag here
# produces an OBS that launches fine and can capture nothing, which is a much
# worse failure than not installing it.
step "OBS capture path"
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would verify obs-studio USE=pipewire"
elif ! have obs; then
    info "obs-studio not installed — skipping check"
elif portageq match / media-video/obs-studio >/dev/null 2>&1 &&
     grep -qw pipewire /var/db/pkg/media-video/obs-studio-*/USE 2>/dev/null; then
    ok "USE=pipewire — portal screen capture available"
else
    err "obs-studio built WITHOUT pipewire: no screen capture on wayland"
    warn "  doas dispatch-conf, then: ./install.sh apps"
fi

# ── EasyEffects: confirm it has plugins to host ────────────────
# Same failure shape as OBS above. EasyEffects is only a host: every effect in
# it is an LV2 plugin from lsp-plugins. Built without USE=lv2 there, the app
# still launches and every effect page is empty — a working GUI that processes
# nothing, which is harder to diagnose than a missing package.
step "EasyEffects plugin path"
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would verify lsp-plugins USE=lv2"
elif ! have easyeffects; then
    info "easyeffects not installed — skipping check"
elif grep -qw lv2 /var/db/pkg/media-libs/lsp-plugins-*/USE 2>/dev/null; then
    ok "lsp-plugins USE=lv2 — effect chain available"
    info "supervised by s6: atlas-svc restart easyeffects | atlas-svc log easyeffects"
else
    err "lsp-plugins built WITHOUT lv2: EasyEffects will host no effects"
    warn "  doas dispatch-conf, then: ./install.sh apps"
fi

ok "apps phase complete"
