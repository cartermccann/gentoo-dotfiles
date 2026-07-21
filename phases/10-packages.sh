#!/usr/bin/env bash
# Phase: packages — Gentoo tree (binhost) + GURU overlay.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

# ── Portage config: keywords + USE ─────────────────────────────
step "portage config (keywords + USE)"
run_root mkdir -p /etc/portage/package.accept_keywords /etc/portage/package.use

kw=/etc/portage/package.accept_keywords/atlas
use=/etc/portage/package.use/atlas
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would write $kw and $use"
else
    as_root tee "$kw" >/dev/null <<'EOF'
gui-wm/mangowm ~amd64
gui-libs/scenefx ~amd64
x11-misc/ly ~amd64
x11-terms/ghostty ~amd64
gui-apps/swaync ~amd64
EOF
    as_root tee "$use" >/dev/null <<'EOF'
x11-misc/rofi wayland
media-video/pipewire sound-server pipewire-alsa
dev-lang/rust-bin clippy rustfmt rust-analyzer rust-src
EOF
    ok "wrote keyword + USE overrides"
fi

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
step "core packages (desktop stack, audio, bluetooth, langs)"
CORE=(
    # compositor + session
    gui-wm/mangowm gui-libs/scenefx x11-misc/ly
    # wayland desktop tools
    gui-apps/waybar gui-apps/swaync gui-apps/swaybg x11-misc/rofi
    gui-apps/wl-clipboard gui-apps/grim gui-apps/slurp gui-apps/swaylock
    gui-apps/wlsunset gui-apps/swayidle gui-apps/wtype
    x11-libs/libnotify media-sound/playerctl
    app-misc/brightnessctl gui-libs/xdg-desktop-portal-wlr
    # terminals + file manager
    x11-terms/ghostty x11-terms/alacritty gui-apps/foot xfce-base/thunar
    # audio
    media-video/pipewire media-video/wireplumber media-sound/pavucontrol
    # bluetooth
    net-wireless/bluez net-wireless/blueman gnome-extra/nm-applet
    # languages / toolchains
    dev-lang/rust-bin dev-lang/go dev-lang/zig net-libs/nodejs
    # shell
    app-shells/fish app-shells/starship
    # fonts
    media-fonts/nerd-fonts media-fonts/noto-emoji
)
LOG="$HOME/.cache/atlas-emerge.log"; mkdir -p "$(dirname "$LOG")"; : > "$LOG"

# Try a qualified atom, then fall back to the bare name (covers a wrong
# category guess); autounmask accepts ~amd64/USE; everything logged.
emerge_pkg() {
    local atom="$1" bare="${1##*/}"
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] emerge $atom"; return 0; }
    echo "### $atom" >> "$LOG"
    as_root emerge --noreplace --quiet --autounmask --autounmask-continue "$atom" >>"$LOG" 2>&1 && return 0
    [ "$bare" = "$atom" ] && return 1
    echo "### retry bare: $bare" >> "$LOG"
    as_root emerge --noreplace --quiet --autounmask --autounmask-continue "$bare" >>"$LOG" 2>&1
}

# CORE as one fast transaction; if it fails, install individually so one bad
# atom can't block the rest of the desktop.
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] emerge ${#CORE[@]} core packages"
elif ! as_root emerge --verbose --noreplace --autounmask --autounmask-write --autounmask-continue "${CORE[@]}"; then
    warn "core batch had issues — installing core packages individually"
    core_missed=()
    for pkg in "${CORE[@]}"; do
        emerge_pkg "$pkg" && ok "$pkg" || { core_missed+=("$pkg"); warn "skipped '$pkg'"; }
    done
    [ ${#core_missed[@]} -gt 0 ] && warn "core unresolved: ${core_missed[*]} (see $LOG)"
fi

# ── CLI tools (resilient: try each, report misses) ─────────────
step "CLI tools (from your kronos toolset)"
# Category-qualified so bare-name ambiguity can't abort them.
TOOLS=(
    sys-apps/ripgrep sys-apps/fd sys-apps/eza sys-apps/bat
    app-shells/zoxide app-shells/atuin app-shells/fzf
    app-misc/yazi app-misc/jq app-misc/yq app-text/tree
    dev-vcs/lazygit dev-vcs/git-lfs dev-util/git-delta dev-util/difftastic
    dev-util/just dev-util/watchexec dev-util/tokei app-benchmarks/hyperfine
    app-text/sd sys-process/procs sys-apps/dust sys-fs/duf sys-apps/broot
    app-misc/tealdeer app-misc/glow app-misc/gum app-arch/ouch net-misc/yt-dlp
    media-sound/cava app-misc/cmatrix games-misc/cbonsai
)
missed=(); _ti=0; _tn=${#TOOLS[@]}
for pkg in "${TOOLS[@]}"; do
    _ti=$((_ti + 1))
    if [ "$DRY_RUN" = "1" ]; then info "would emerge $pkg"; continue; fi
    progress "$_ti" "$_tn" "${pkg##*/}"
    emerge_pkg "$pkg" || missed+=("$pkg")
done
[ "$DRY_RUN" = "1" ] || { progress "$_tn" "$_tn" "done"; printf '\n'; }
ok "$(( _tn - ${#missed[@]} ))/$_tn tools installed"
if [ ${#missed[@]} -gt 0 ]; then
    warn "unresolved: ${missed[*]}"
    warn "  reasons: $LOG   ·   find the right atom with:  emerge -s <name>"
    warn "  if keyword/USE changes were written: doas dispatch-conf && ./install.sh packages"
fi

# ── Wayland session entry for ly ───────────────────────────────
step "mango wayland session (for ly)"
sess=/usr/share/wayland-sessions/mango.desktop
if [ -f "$sess" ]; then
    ok "session file present"
elif [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would create $sess"
else
    as_root tee "$sess" >/dev/null <<'EOF'
[Desktop Entry]
Name=Mango
Comment=dwl-based Wayland compositor
Exec=mango
Type=Application
EOF
    ok "created $sess"
fi

# ── Services ───────────────────────────────────────────────────
step "enable services"
run_root rc-update add dbus default
run_root rc-update add elogind boot
run_root rc-update add NetworkManager default
run_root rc-update add bluetooth default
run_root rc-update add ly default
ok "services queued (dbus, elogind, NetworkManager, bluetooth, ly)"
warn "ly takes over a tty at boot — if you hit a getty conflict, see README."

ok "packages phase complete"
