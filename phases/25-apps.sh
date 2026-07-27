#!/usr/bin/env bash
# Phase: apps — GUI applications that ARE packaged for Gentoo.
#
# Separate from 10-packages (the desktop stack + CLI, which the machine needs
# to boot into a usable session) and from 20-flatpaks (GUI apps Gentoo does
# NOT package). This is the middle case: desktop software with a real ebuild,
# all of it optional, none of it load-bearing. Run it or don't — nothing else
# in the repo depends on anything here.
#
# All four are proprietary binary repacks, which is why they all needed a
# keyword line in system/portage/package.accept_keywords/atlas.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

LOG="$HOME/.cache/atlas-emerge.log"; mkdir -p "$(dirname "$LOG")"

APPS=(
    app-office/obsidian         # notes vault
    gui-apps/1password          # GUI
    app-misc/1password-cli      # `op` — the CLI is a separate package
    net-im/slack
    media-video/obs-studio      # USE flags matter here, see package.use/atlas
    # The browser. It IS installed from portage (-> /opt/zen), not flatpak, and
    # was undeclared until 2026-07-26 — so a clean checkout produced a machine
    # with no browser at all. Its ~amd64 keyword line was undeclared too, in a
    # stray /etc/portage/package.accept_keywords/zen-bin that this repo has now
    # absorbed.
    www-client/zen-bin
)

emerge_app() {
    local atom="$1"
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] emerge $atom"; return 0; }
    echo "### $atom" >> "$LOG"
    as_root emerge --noreplace --quiet --autounmask --autounmask-continue "$atom" \
        >>"$LOG" 2>&1
}

step "desktop applications"
missed=(); _i=0; _n=${#APPS[@]}
for pkg in "${APPS[@]}"; do
    _i=$((_i + 1))
    if [ "$DRY_RUN" = "1" ]; then info "would emerge $pkg"; continue; fi
    progress "$_i" "$_n" "${pkg##*/}"
    emerge_app "$pkg" || missed+=("$pkg")
done
[ "$DRY_RUN" = "1" ] || { progress "$_n" "$_n" "done"; printf '\n'; }
ok "$(( _n - ${#missed[@]} ))/$_n apps installed"
if [ ${#missed[@]} -gt 0 ]; then
    warn "unresolved: ${missed[*]}"
    warn "  reasons: $LOG"
    warn "  if keyword/USE changes were written: doas dispatch-conf && ./install.sh apps"
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

ok "apps phase complete"
