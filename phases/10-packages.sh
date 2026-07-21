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
gui-apps/ghostty ~amd64
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
    gui-apps/ghostty x11-terms/alacritty gui-apps/foot xfce-base/thunar
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
run_root emerge --verbose --autounmask --autounmask-write --autounmask-continue "${CORE[@]}" \
    || warn "core emerge reported issues — review output above (may need a USE/keyword accept, then re-run)"

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
missed=()
log="$HOME/.cache/atlas-tools-emerge.log"; mkdir -p "$(dirname "$log")"; : > "$log"
for pkg in "${TOOLS[@]}"; do
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] emerge $pkg"; continue; fi
    echo "### $pkg" >> "$log"
    if as_root emerge --noreplace --quiet --autounmask --autounmask-continue "$pkg" >>"$log" 2>&1; then
        ok "$pkg"
    else
        missed+=("$pkg"); warn "skipped '$pkg'"
    fi
done
if [ ${#missed[@]} -gt 0 ]; then
    warn "unresolved: ${missed[*]}"
    warn "  reasons logged to $log   ·   find a right atom with:  emerge -s <name>"
    warn "  if the log shows keyword/USE changes were written, run: doas dispatch-conf && ./install.sh packages"
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
