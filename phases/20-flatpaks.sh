#!/usr/bin/env bash
# Phase: flatpaks — GUI apps Gentoo doesn't package.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

step "flatpak + flathub"
if ! have flatpak; then
    run_root emerge --noreplace --quiet sys-apps/flatpak
fi
run_root flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

# app-id list. Helium is very new — it may not be on Flathub yet;
# if the install fails, grab its AppImage from the project releases.
FLATPAKS=(
    app.zen_browser.zen          # Zen browser
    com.spotify.Client           # Spotify
    com.beeper.Beeper            # Beeper
    com.rafaelmardojai.Blanket   # Blanket (ambient sound)
)

step "install flatpak apps"
for id in "${FLATPAKS[@]}"; do
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] flatpak install $id"; continue; fi
    if flatpak install -y --noninteractive flathub "$id" >/dev/null 2>&1; then
        ok "$id"
    else
        warn "could not install $id (check the app-id on flathub.org)"
    fi
done

warn "Helium browser: not on Flathub as of setup — install its AppImage from"
warn "  https://github.com/imputnet/helium-chromium/releases  (then chmod +x)"

ok "flatpaks phase complete"
