#!/usr/bin/env bash
# Phase: flatpaks — GUI apps Gentoo doesn't package.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

step "flatpak + flathub"
if ! have flatpak; then
    run_root emerge --noreplace --quiet sys-apps/flatpak
fi
# --user throughout: no root needed, and it keeps the runtime set in
# ~/.local/share/flatpak so a re-run doesn't re-download a second system copy.
run flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# Verified present on Flathub (checked against `flatpak remote-info`).
FLATPAKS=(
    # Zen is NOT here: it is installed from portage as www-client/zen-bin
    # (-> /opt/zen), which is what /usr/bin/zen runs and where the profile
    # lives. The flatpak was a second, unused copy of the same browser —
    # 761 MB of app data nothing ever launched. Removed 2026-07-26; the
    # keyword for the portage build is in package.accept_keywords/atlas.
    com.spotify.Client           # Spotify
    com.rafaelmardojai.Blanket   # Blanket (ambient sound)
)

step "install flatpak apps"
for id in "${FLATPAKS[@]}"; do
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] flatpak install --user $id"; continue; fi
    if flatpak list --user --app --columns=application 2>/dev/null | grep -qx "$id"; then
        ok "$id (already)"
    elif flatpak install --user -y --noninteractive flathub "$id" >/dev/null 2>&1; then
        # note: Spotify prints a wall of "lseek error in child setup" from
        # bwrap while unpacking. It is noise; the install still succeeds.
        ok "$id"
    else
        warn "could not install $id (check the app-id on flathub.org)"
    fi
done

# Neither of these is on Flathub — verified, not assumed:
#   `flatpak search beeper`  -> no matches
#   `flatpak search helium`  -> only org.gtk.Gtk3theme.Helium (a GTK theme)
step "not available via flatpak"
warn "Beeper: no Flathub app-id exists. Download the Linux build from"
warn "  https://www.beeper.com/download  (AppImage) -> ~/.local/bin/, chmod +x"
warn "Helium browser: not on Flathub either. AppImage from"
warn "  https://github.com/imputnet/helium-chromium/releases  (then chmod +x)"

ok "flatpaks phase complete"
