#!/usr/bin/env bash
# Phase: services — install the s6 user supervision tree.
#
# OpenRC's *system* runlevels are system-wide and root-owned, which is the wrong
# shape for daemons that belong to a graphical session. This builds a per-user
# supervision tree instead.
#
# Note that OpenRC 0.62+ does have user services, and they are enabled on this
# machine — s6 is a deliberate choice here, not a workaround for a missing
# feature. services/README.md has the current reasoning and the conditions
# under which it should be revisited.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

SCAN="$HOME/.local/state/s6/scan"
LOGS="$HOME/.local/state/s6/log"

step "s6 present?"
if ! have s6-svscan; then
    err "s6 is not installed — run ./install.sh packages first"
    exit 1
fi
ok "s6-svscan $(s6-svscan -h 2>&1 | head -1 | grep -oE 's6-[0-9.]+' || echo present)"

# ── Scan directory ─────────────────────────────────────────────
# State, not configuration: the scan dir holds s6's own control fifos and the
# rotated logs, so it lives under ~/.local/state and is never in the repo.
step "scan directory"
run mkdir -p "$SCAN" "$LOGS"
ok "${SCAN/#$HOME/\~}"

# ── Seed each service definition, link it into the scan dir ────
#
# Definitions live at ~/.config/s6/<name> (the LIVE home — contract flipped
# 2026-08-05; the repo only seeds them). The scan directory holds symlinks to
# ~/.config/s6, which is normal s6 practice: scan is state, ~/.config is
# config. s6 writes its supervise/ and event/ runtime dirs through the link
# into ~/.config/s6/<name>/ — that is s6's own layout, leave it be.
CONF="$HOME/.config/s6"
step "service definitions"
count=0
for dir in "$REPO_DIR"/services/*/; do
    name="$(basename "${dir%/}")"
    [ -f "$dir/run" ] || continue          # README.md and friends are not services
    seed_copy "${dir%/}" "$CONF/$name"
    run chmod +x "$CONF/$name/run" "$CONF/$name/log/run" 2>/dev/null
    run mkdir -p "$LOGS/$name"
    run ln -sfn "$CONF/$name" "$SCAN/$name"
    count=$((count + 1))
done
ok "$count service(s) defined"

# ── Control wrapper ────────────────────────────────────────────
step "atlas-svc"
run mkdir -p "$HOME/.local/bin"
run chmod +x "$REPO_DIR/bin/atlas-svc"
seed_copy "$REPO_DIR/bin/atlas-svc" "$HOME/.local/bin/atlas-svc"

# ── Pick up the new definitions ────────────────────────────────
# If a supervisor is already running (i.e. this is a re-run inside a live
# session), tell it to rescan. If not, autostart.sh will start one at the next
# login — deliberately not started here, because a supervision tree launched
# from an installer would not be a child of the session and would outlive it.
step "activate"
if pgrep -u "$USER" -x s6-svscan >/dev/null 2>&1; then
    run s6-svscanctl -a "$SCAN" && ok "running supervisor rescanned"
else
    info "no supervisor running — it starts with the next session (autostart.sh)"
    info "to start one now without logging out:  s6-svscan $SCAN &"
fi

ok "services phase complete"
