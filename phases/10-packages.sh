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
# diff and edit. deploy_system_file copies and reports drift rather than
# symlinking: /etc/portage decides what root emerges, so pointing it at a
# user-writable git checkout would be a privilege-escalation path.
deploy_system_file() {   # src dst mode
    local src="$1" dst="$2" mode="${3:-0644}"
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] install $src -> $dst"; return; fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        ok "${dst} (unchanged)"
    else
        # Backups go to a directory of their own, NOT beside the target. Writing
        # "$dst.bak.<stamp>" put files portage does not own into
        # /etc/portage/package.*, where --check's stray scan then correctly
        # reported them as UNDECLARED — this function was manufacturing the exact
        # drift the check exists to find.
        if [ -f "$dst" ]; then
            as_root mkdir -p "$CONFIG_BACKUP_DIR"
            as_root cp "$dst" \
                "$CONFIG_BACKUP_DIR/$(echo "${dst#/}" | tr / _).$(date +%Y%m%d-%H%M%S)"
        fi
        as_root install -D -m "$mode" "$src" "$dst" && ok "${dst}"
    fi
}

deploy_system_file "$REPO_DIR/system/portage/package.accept_keywords/atlas" \
                   /etc/portage/package.accept_keywords/atlas
deploy_system_file "$REPO_DIR/system/portage/package.use/atlas" \
                   /etc/portage/package.use/atlas
deploy_system_file "$REPO_DIR/system/portage/package.license/atlas" \
                   /etc/portage/package.license/atlas
deploy_system_file "$REPO_DIR/system/portage/package.mask/atlas" \
                   /etc/portage/package.mask/atlas

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
    # ── The base the handbook install left behind ──────────────
    # Everything in this block was installed by hand during the original Gentoo
    # install and then never declared, so `--check`'s @world diff found all of it
    # missing on 2026-07-26. A clean checkout would have produced a machine with
    # no kernel, no privilege escalation, no network and no session — while
    # system/services.conf cheerfully declared dbus, elogind and NetworkManager
    # as services to *enable*, with nothing to install them.
    #
    # The kernel. dist-kernel (see make.conf USE) so updates rebuild the
    # initramfs and run the hooks in system/kernel/postinst.d.
    sys-kernel/gentoo-kernel-bin sys-kernel/linux-firmware
    # doas is what install.sh itself escalates with — lib/common.sh prefers it
    # over sudo. The installer depended on a package the installer never installed.
    app-admin/doas
    # session + device plumbing. seatd and elogind are what let a non-root user
    # own the seat mango runs on; dbus is required by half the desktop.
    sys-apps/dbus sys-auth/elogind sys-auth/seatd
    # network + time + logs. chrony matters more than it looks: a skewed clock
    # breaks TLS, and therefore breaks emerge against the binhost.
    net-misc/networkmanager net-misc/chrony app-admin/sysklogd
    # btrfs is the root filesystem (subvols @, @home, @snapshots) — without the
    # userspace tools there is no scrub, no snapshot, no resize. btrbk drives
    # the snapshots: /.snapshots had been mounted since the install with nothing
    # ever writing to it. Config and rollback notes in system/btrbk/.
    sys-fs/btrfs-progs app-backup/btrbk
    # vulkan loader: mango/scenefx render through it, and usbutils is how the
    # Codex Micro HID path gets debugged when it stops enumerating.
    media-libs/vulkan-loader sys-apps/usbutils
    # Limine is the bootloader (bin/setup-limine installs and configures it).
    # grub is NOT here: it was installed but unused, second in BootOrder with a
    # stale config, and it was removed on 2026-07-26. efibootmgr below is
    # what remains of that: keep it.
    #
    # efibootmgr is declared explicitly BECAUSE of that removal. It had only
    # ever been present as a grub dependency, so depclean listed it for removal
    # alongside grub — and it is the only tool that can read or repair the NVRAM
    # entry this machine now depends on for booting. If that entry is ever lost,
    # recovery is `efibootmgr -c -d /dev/nvme0n1 -p 1 -L Limine -l
    # '\EFI\Limine\BOOTX64.EFI'`, which is impossible without it installed.
    sys-boot/limine sys-boot/efibootmgr

    # compositor + session
    gui-wm/mangowm gui-libs/scenefx
    # login: ly. Not in CORE — it needs the GURU Manifest workaround in
    # bin/setup-ly, which must be an explicit, auditable step.
    # wayland desktop tools
    gui-apps/waybar gui-apps/swaync gui-apps/swaybg x11-misc/rofi
    gui-apps/wl-clipboard app-misc/cliphist gui-apps/grim gui-apps/slurp gui-apps/swaylock
    gui-apps/wlsunset gui-apps/swayidle gui-apps/wtype
    x11-libs/libnotify media-sound/playerctl
    app-misc/brightnessctl gui-libs/xdg-desktop-portal-wlr
    # terminals + file manager + editor
    x11-terms/ghostty x11-terms/alacritty xfce-base/thunar
    app-editors/neovim
    # audio
    media-video/pipewire media-video/wireplumber media-sound/pavucontrol
    # bluetooth
    net-wireless/bluez net-wireless/blueman gnome-extra/nm-applet
    # languages / toolchains
    dev-lang/rust-bin dev-lang/go dev-lang/zig net-libs/nodejs
    # shell
    app-shells/fish app-shells/starship
    # cursor theme (matches kronos)
    x11-themes/bibata-xcursors
    # fonts  (atom is nerdfonts, no hyphen — and it lives in GURU)
    media-fonts/nerdfonts media-fonts/noto-emoji
    # console font for the ly greeter — see system/conf.d/consolefont.
    # Load-bearing, not cosmetic: consolefont names ter-u24b, and if the
    # package is absent the service falls back to the tiny 8x16 default.
    media-fonts/terminus-font
    # session supervision — s6 runs the user services in services/. Not
    # optional: config/mango/autostart.sh starts a tree over them at login.
    sys-apps/s6 sys-apps/s6-rc
    # runtime for the vendored Electron bundles in ~/apps (phases/27-vendored).
    # Chromium dlopen()s libcups even with printing unused, and the Codex
    # Micro's HID path goes through libusb. Both are the difference between an
    # app that starts and one that dies with a bare "not found".
    net-print/cups dev-libs/libusb
    # webkit-gtk[wayland] is the same situation one step further out: NOTHING in
    # portage depends on it (`equery depends` returns empty), so it looks like an
    # 83 MB orphan that depclean should take. It is not. ~/apps/buzz is a Tauri v2
    # app, and Tauri renders through wry -> libwebkit2gtk-4.1. Portage cannot see
    # that dependency because buzz is not a portage package, so the only thing
    # standing between it and a depclean is this line. The `wayland` USE flag
    # matters too (see package.use/atlas) — without it the web views go through
    # XWayland.
    net-libs/webkit-gtk
    # remote access — the LAN address changes, tailscale does not. `tailscale
    # up` still has to be run by hand once; nothing here authenticates.
    net-vpn/tailscale
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
    # Five of these were in the wrong category until 2026-07-26 (dev-util/just,
    # dev-util/watchexec, app-text/sd, sys-apps/dust, sys-apps/broot). They still
    # installed, because emerge_pkg retries the bare name — the log showed five
    # `retry bare:` lines every run. That fallback is worth keeping as a safety
    # net, but relying on it costs a failed resolution pass per atom and hides
    # real typos, so the categories are now correct. sd and watchexec are GURU.
    dev-build/just app-misc/watchexec dev-util/tokei app-benchmarks/hyperfine
    sys-apps/sd sys-process/procs sys-block/dust sys-fs/duf app-misc/broot
    app-misc/tealdeer app-misc/glow app-arch/ouch net-misc/yt-dlp
    media-sound/cava app-misc/cmatrix games-misc/cbonsai
    # btop is the process viewer config/btop themes, fastfetch is what the
    # kronos-style greeting would use, and github-cli is not optional: it is the
    # git credential helper in ~/.gitconfig, so without it every push to GitHub
    # fails to authenticate on a freshly built machine.
    sys-process/btop app-misc/fastfetch dev-util/github-cli
    # terminal workflow — config/tmux and the fish functions depend on these:
    # `dev` and `t` are tmux wrappers, and config.fish hooks direnv if present.
    app-misc/tmux app-shells/direnv app-misc/television
    # portage maintenance. Not optional in practice: eclean-dist is the only
    # supported way to prune /var/cache/distfiles (3.7 GB and growing),
    # revdep-rebuild finds binaries left linking against removed libraries
    # after a depclean, and equery answers "what pulled this in" — all three
    # were wanted during the 2026-07-26 audit and none were present.
    app-portage/gentoolkit
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
if [ "$DRY_RUN" != "1" ]; then
    as_root install -D -m 0755 "$REPO_DIR/system/bin/mango-session" /usr/local/bin/mango-session
    ok "/usr/local/bin/mango-session"
fi
sess=/usr/share/wayland-sessions/mango.desktop
# Always rewrite: the Exec line changed once already (mango -> mango-session)
# and a stale "session file present" check would have silently kept the old one.
if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would create $sess"
else
    as_root tee "$sess" >/dev/null <<'EOF'
[Desktop Entry]
Encoding=UTF-8
Name=Mango
Comment=dwl-based Wayland compositor
DesktopNames=mango;wlroots
# See system/bin/mango-session — it supplies both the D-Bus session bus and
# XCURSOR_THEME/SIZE, neither of which mango can set for itself.
Exec=/usr/local/bin/mango-session
Type=Application
EOF
    ok "created $sess"
fi

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
