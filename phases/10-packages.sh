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
x11-terms/ghostty ~amd64
gui-apps/swaync ~amd64
media-fonts/nerdfonts ~amd64
# pre-seeded so autounmask doesn't have to write them mid-run (which leaves
# ._cfg files behind and stalls the batch)
=x11-terms/ghostty-terminfo-1.3.1 ~amd64
=dev-lang/zig-bin-0.15.2 ~amd64
=app-misc/brightnessctl-0.5.1 ~amd64
=gui-apps/wtype-0.4 ~amd64
=gui-apps/wlsunset-0.4.0 ~amd64
EOF
    as_root tee "$use" >/dev/null <<'EOF'
x11-misc/rofi wayland
media-video/pipewire sound-server pipewire-alsa
dev-lang/rust-bin clippy rustfmt rust-analyzer rust-src
net-libs/nodejs npm

# ── REQUIRED_USE "any-of ( wayland X )" ────────────────────────
# The base 23.0 profile sets neither X nor wayland, so every package with
# this constraint hard-fails. autounmask writes keywords but will NOT flip a
# REQUIRED_USE flag, so these must be declared up front.
x11-terms/ghostty wayland
dev-cpp/gtkmm wayland X
dev-cpp/cairomm wayland X
x11-libs/cairo X
xfce-base/xfce4-panel wayland
xfce-base/libxfce4ui wayland
xfce-base/libxfce4windowing wayland X
xfce-base/xfce4-appfinder wayland
xfce-base/exo wayland

# ── swaync / gtk4 stack (else mesa+gtk get rebuilt without wayland) ──
>=gui-libs/gtk4-layer-shell-1.1.1-r1 introspection vala
gui-libs/gtk wayland
media-libs/mesa wayland

# ── dist-kernel ────────────────────────────────────────────────
sys-kernel/installkernel dracut
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
    gui-wm/mangowm gui-libs/scenefx
    # login: greetd + tuigreet (x11-misc/ly's only ebuild 404s upstream)
    gui-libs/greetd gui-apps/tuigreet
    # wayland desktop tools
    gui-apps/waybar gui-apps/swaync gui-apps/swaybg x11-misc/rofi
    gui-apps/wl-clipboard gui-apps/grim gui-apps/slurp gui-apps/swaylock
    gui-apps/wlsunset gui-apps/swayidle gui-apps/wtype
    x11-libs/libnotify media-sound/playerctl
    app-misc/brightnessctl gui-libs/xdg-desktop-portal-wlr
    # terminals + file manager + editor
    x11-terms/ghostty x11-terms/alacritty gui-apps/foot xfce-base/thunar
    app-editors/neovim
    # audio
    media-video/pipewire media-video/wireplumber media-sound/pavucontrol
    # bluetooth
    net-wireless/bluez net-wireless/blueman gnome-extra/nm-applet
    # languages / toolchains
    dev-lang/rust-bin dev-lang/go dev-lang/zig net-libs/nodejs
    # shell
    app-shells/fish app-shells/starship
    # fonts  (atom is nerdfonts, no hyphen — and it lives in GURU)
    media-fonts/nerdfonts media-fonts/noto-emoji
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
    app-misc/tealdeer app-misc/glow app-arch/ouch net-misc/yt-dlp
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

# ── greetd: config + OpenRC init script ────────────────────────
# The Gentoo package ships only a systemd unit, so OpenRC needs ours.
step "greetd (login manager)"
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would install /etc/greetd/config.toml and /etc/init.d/greetd"
elif have greetd; then
    run_root mkdir -p /etc/greetd
    as_root install -m 0644 "$REPO_DIR/system/greetd/config.toml" /etc/greetd/config.toml
    as_root install -m 0755 "$REPO_DIR/system/init.d/greetd"      /etc/init.d/greetd
    ok "greetd config + OpenRC init script installed (greeter on vt7)"
else
    warn "greetd not installed — skipping its config"
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
add_svc dbus default
add_svc elogind boot
add_svc NetworkManager default
add_svc bluetooth default
add_svc greetd default
if [ ${#svc_missing[@]} -gt 0 ]; then
    warn "services NOT enabled (missing packages): ${svc_missing[*]}"
    warn "  install them, then re-run: ./install.sh packages"
fi
warn "greetd owns vt1 at boot — if you hit an agetty conflict, see README."

ok "packages phase complete"
