#!/usr/bin/env bash
# Mango autostart — launched once per session (exec-once in config.conf).
# Resilient: each helper only runs if the command exists, so a missing
# optional tool never breaks the session.
set +e

# Guard FIRST, then background a simple command.
#
# The obvious one-liner -- `command -v "$1" >/dev/null && "$@" &` -- backgrounds
# a COMPOUND, so bash has to fork a subshell to hold the && and that subshell
# lingers as a second process per service, showing up as another
# "bash autostart.sh". Splitting the guard out means `"$@" &` is a simple
# command, which bash execs directly. One process per service, not two.
run() {
    command -v "$1" >/dev/null 2>&1 || return 0
    "$@" &
}

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
# Wallpaper — see bin/atlas-wallpaper (shared with atlas-theme).
if [ -x "$HOME/gentoo-dotfiles/bin/atlas-wallpaper" ]; then
    "$HOME/gentoo-dotfiles/bin/atlas-wallpaper"
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
# blueman-applet is deliberately NOT started. It ships a full-colour tray
# pixmap that waybar cannot restyle, so it was the one saturated thing in an
# otherwise monochrome bar. The waybar `bluetooth` module already shows state
# and opens blueman-manager on click.
#
# Tradeoff, so it is not a surprise later: blueman-applet is also the GUI
# pairing agent. Incoming pair requests will not raise a dialog on their own
# now -- open blueman-manager (click the BT chip) and it registers an agent
# while it is open. Start `blueman-applet` by hand if you ever want the old
# behaviour back.
# nm-applet is deliberately NOT started, for the same reason as blueman-applet.
#
# It never actually ran here: gnome-extra/nm-applet is built with -appindicator
# on this box, so `--indicator` aborts at startup with "indicator support not
# available" and the process dies. That one line was the error flashing past on
# every login, and pgrep confirmed nothing survived.
#
# Nothing is lost by dropping it. The waybar `network` module already shows
# wifi/signal/IP and opens `nmtui` in ghostty on click, which is where you join
# a new network or enter a password. Rebuilding with USE=appindicator would put
# a tray icon back, but it would be another full-colour pixmap in a monochrome
# bar -- exactly what blueman-applet was removed for.

# ── Polkit agent (auth dialogs) ────────────────────────────────
run /usr/libexec/polkit-gnome-authentication-agent-1

# ── XDG desktop portal (screenshare / file pickers) ────────────
run /usr/libexec/xdg-desktop-portal-wlr
