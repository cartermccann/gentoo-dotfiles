#!/usr/bin/env bash
# Mango autostart — launched once per session (exec-once in config.conf).
# Resilient: each helper only runs if the command exists, so a missing
# optional tool never breaks the session.
set +e

run() { command -v "$1" >/dev/null 2>&1 && "$@" & }

# ── D-Bus activation environment ───────────────────────────────
# Without this, D-Bus-activated services and anything using the session bus
# fail with "Cannot autolaunch D-Bus without X11 $DISPLAY". That is what kept
# waybar, swaync, nm-applet and blueman-applet down while swaybg, pipewire and
# wlsunset (which need no bus) came up fine.
# The session itself is wrapped in dbus-run-session by mango.desktop; this
# pushes the wayland vars into the bus so activated children inherit them.
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --all \
        WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR 2>/dev/null
fi

# ── Wallpaper (image if present, else solid Catppuccin base) ───
# First image found in the wallpaper dir wins; falls back to the current
# theme's GROUND colour rather than a hardcoded Catppuccin base.
_wp=$(find "$HOME/.config/mango/wallpaper" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | sort | head -1)
if [ -n "$_wp" ]; then
    run swaybg -i "$_wp" -m fill
else
    _ground=$(sed -n 's/^GROUND=//p' \
        "$HOME/gentoo-dotfiles/themes/$(cat "$HOME/.local/state/atlas/current-theme" 2>/dev/null || echo cobalt)/colors.sh" 2>/dev/null)
    run swaybg -c "${_ground:-0a0c11}"
fi

# ── Audio (PipeWire — started from the session on OpenRC) ───────
run pipewire
run wireplumber
run pipewire-pulse

# ── Bar + notification center ──────────────────────────────────
run waybar
run swaync

# ── Night light ────────────────────────────────────────────────
run wlsunset -l 34.05 -L -118.24

# ── Idle: lock after 5 min, and lock before sleep ──────────────
run swayidle -w timeout 300 "swaylock -f" before-sleep "swaylock -f"

# ── Clipboard history (needs cliphist + wl-clipboard) ──────────
# Two watchers: wl-paste defaults to text only, so images need their own.
# Both must run for the whole session or SUPER+V has nothing to show.
run wl-paste --type text  --watch cliphist store
run wl-paste --type image --watch cliphist store

# ── Tray applets ───────────────────────────────────────────────
run nm-applet --indicator
run blueman-applet

# ── Polkit agent (auth dialogs) ────────────────────────────────
run /usr/libexec/polkit-gnome-authentication-agent-1

# ── XDG desktop portal (screenshare / file pickers) ────────────
run /usr/libexec/xdg-desktop-portal-wlr
