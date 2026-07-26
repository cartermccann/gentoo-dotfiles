#!/usr/bin/env bash
# Phase: services — install the s6 user supervision tree.
#
# OpenRC's runlevels are system-wide and root-owned, which is the wrong shape
# for daemons that belong to a graphical session. This builds a per-user
# supervision tree instead; see services/README.md for the reasoning.
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

# ── Link each service definition into the scan directory ───────
#
# Symlinked, not copied — unlike /etc, nothing here decides what root does, so
# pointing at the checkout is safe and means editing a `run` script and
# restarting is a two-step loop rather than a redeploy.
step "service definitions"
count=0
for dir in "$REPO_DIR"/services/*/; do
    name="$(basename "${dir%/}")"
    [ -f "$dir/run" ] || continue          # README.md and friends are not services
    run chmod +x "$dir/run" "$dir/log/run" 2>/dev/null
    run mkdir -p "$LOGS/$name"
    backup_and_link "${dir%/}" "$SCAN/$name"
    count=$((count + 1))
done
ok "$count service(s) linked"

# ── Control wrapper ────────────────────────────────────────────
step "atlas-svc"
run mkdir -p "$HOME/.local/bin"
run chmod +x "$REPO_DIR/bin/atlas-svc"
backup_and_link "$REPO_DIR/bin/atlas-svc" "$HOME/.local/bin/atlas-svc"

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
