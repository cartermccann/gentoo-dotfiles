#!/usr/bin/env bash
# Mango autostart — launched once per session (exec-once in config.conf).
# Resilient: each helper only runs if the command exists, so a missing
# optional tool never breaks the session.
set +e

run() { command -v "$1" >/dev/null 2>&1 && "$@" & }

# ── Wallpaper (image if present, else solid Catppuccin base) ───
if [ -f "$HOME/.config/mango/wallpaper/wallpaper.png" ]; then
    run swaybg -i "$HOME/.config/mango/wallpaper/wallpaper.png" -m fill
else
    run swaybg -c 1e1e2e
fi

# ── Audio (PipeWire — started from the session on OpenRC) ───────
run pipewire
run wireplumber
run pipewire-pulse

# ── Bar + notifications ────────────────────────────────────────
run waybar
run mako

# ── Night light ────────────────────────────────────────────────
run wlsunset -l 34.05 -L -118.24

# ── Idle: lock after 5 min, and lock before sleep ──────────────
run swayidle -w timeout 300 "swaylock -f" before-sleep "swaylock -f"

# ── Clipboard history (needs cliphist + wl-clipboard) ──────────
run wl-paste --watch cliphist store

# ── Tray applets ───────────────────────────────────────────────
run nm-applet --indicator
run blueman-applet

# ── Polkit agent (auth dialogs) ────────────────────────────────
run /usr/libexec/polkit-gnome-authentication-agent-1

# ── XDG desktop portal (screenshare / file pickers) ────────────
run /usr/libexec/xdg-desktop-portal-wlr
