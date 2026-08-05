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
#
# Each launch is also RECORDED, so that check_started (bottom of this file) can
# report the ones that did not survive. Fire-and-forget is still the contract --
# nothing here is restarted, that is what the s6 tree at the bottom is for --
# but "died instantly" and "started fine" used to look identical, and that is
# how swayidle managed to exit 255 at every login since this machine was built
# without anyone noticing the screen had never once auto-locked.
_launched=()
run() {
    command -v "$1" >/dev/null 2>&1 || return 0
    "$@" &
    _launched+=("$!|$*")
}

# Report anything that did not survive its first few seconds.
#
# Runs backgrounded so it never delays the session, and the subshell exits as
# soon as it has reported -- the one-process-per-service concern above still
# holds for the steady state.
#
# The delay is a compromise, and worth stating rather than tuning blindly: it
# catches "never started", which is the failure mode actually observed here
# (bad USE flag, missing bus, aborted on an unsupported argument -- all of which
# die immediately). It will NOT catch something that dies an hour in. Supervise
# it in services/ if that matters for a given daemon.
check_started() {
    local grace=5 dead=() e pid cmd
    sleep "$grace"
    for e in "${_launched[@]}"; do
        pid=${e%%|*}; cmd=${e#*|}
        kill -0 "$pid" 2>/dev/null || dead+=("$cmd")
    done
    [ ${#dead[@]} -eq 0 ] && return 0
    # stderr, because mango-session appends it to ~/.cache/mango-session.log --
    # the one place that survives the session and gets read after the fact.
    {
        echo "─── autostart: ${#dead[@]} service(s) died within ${grace}s ───"
        printf '  %s\n' "${dead[@]}"
        echo "─── rerun one by hand to see its error ───"
    } >&2
    # Best-effort desktop notice. Deliberately not relied on: swaync is itself
    # one of the things that can be in the dead list.
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "autostart: ${#dead[@]} service(s) failed" \
            "$(printf '%s\n' "${dead[@]}")" 2>/dev/null
    fi
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

# ── Wallpaper (image if present, else solid theme ground) ──────
# Wallpaper — see ~/.local/bin/atlas-wallpaper (shared with atlas-theme).
if [ -x "$HOME/.local/bin/atlas-wallpaper" ]; then
    "$HOME/.local/bin/atlas-wallpaper"
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

# ── User services (s6 supervision tree) ────────────────────────
# Everything above is fire-and-forget: if it dies, the session is slightly
# worse until the next login. That is the wrong contract for daemons whose job
# is recovering from failure, so those live in a supervised tree instead.
# Definitions are in the repo under services/; see services/README.md.
#
# One supervisor per session. `-d` is not a thing for s6-svscan, so guard on an
# existing one rather than relying on it to refuse: a second svscan over the
# same scan directory fights the first for the control fifos.
S6_SCAN="$HOME/.local/state/s6/scan"
if command -v s6-svscan >/dev/null 2>&1 && [ -d "$S6_SCAN" ]; then
    if pgrep -u "$USER" -x s6-svscan >/dev/null 2>&1; then
        s6-svscanctl -a "$S6_SCAN" 2>/dev/null
    else
        s6-svscan "$S6_SCAN" &
    fi
fi

# ── Did any of the above die immediately? ──────────────────────
# Last, so every `run` above has been recorded. Backgrounded: this sleeps
# before reporting and must not hold up the session.
check_started &
