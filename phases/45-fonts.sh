#!/usr/bin/env bash
# Phase: fonts — UI typeface (Geist) alongside the terminal Nerd Font.
#
# WHY THIS IS NOT AN EMERGE: Geist is not in the Gentoo tree (checked
# media-fonts/geist, absent), and neither is Inter. Open Sans and Noto are, but
# they are humanist/neutral rather than the geometric sans this desktop wants.
# So Geist is fetched from upstream releases into ~/.local/share/fonts, which is
# user-owned and needs no root -- the one imperative install on the box, kept in
# this script rather than done by hand so it is reproducible.
#
# THE TRAP, and it is the same one that bit the ly clock: a UI font does NOT
# carry Nerd Font icon glyphs. waybar and rofi draw their module icons from the
# Material Design range (U+F0425 power, U+F033E lock, ...), and NOTHING outside
# a patched Nerd Font has them. So every UI surface must specify a font STACK
# with JetBrainsMono Nerd Font as the fallback, never Geist alone -- otherwise
# every icon in the bar becomes a tofu box. Verify after changing a font with:
#
#   fc-list ':charset=F0425' family
#
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

FONT_DIR="$HOME/.local/share/fonts"
GEIST_DIR="$FONT_DIR/geist"
GEIST_REPO="vercel/geist-font"

step "Geist (UI typeface)"

if fc-list : family 2>/dev/null | tr ',' '\n' | grep -qix "Geist"; then
    ok "Geist already installed"
else
    run mkdir -p "$GEIST_DIR"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    # Resolve the latest release asset rather than pinning a URL that rots.
    url="$(curl -fsSL "https://api.github.com/repos/$GEIST_REPO/releases/latest" \
           | grep -oE '"browser_download_url"[^,]*\.zip"' \
           | cut -d'"' -f4 | head -1)"

    if [ -z "$url" ]; then
        warn "could not resolve a Geist release asset — skipping"
        warn "install by hand into $GEIST_DIR, then re-run this phase"
    else
        info "fetching $(basename "$url")"
        if curl -fsSL -o "$tmp/geist.zip" "$url"; then
            # Take the variable fonts if present, else the statics. Either way
            # only .ttf/.otf, never the whole repo tree.
            (cd "$tmp" && unzip -qo geist.zip)
            found=$(find "$tmp" -type f \( -name '*.ttf' -o -name '*.otf' \) | wc -l)
            if [ "$found" -gt 0 ]; then
                find "$tmp" -type f \( -name '*.ttf' -o -name '*.otf' \) \
                    -exec cp -f {} "$GEIST_DIR/" \;
                ok "installed $found font file(s) to $GEIST_DIR"
            else
                warn "release zip contained no .ttf/.otf"
            fi
        else
            warn "download failed — leaving fonts unchanged"
        fi
    fi
fi

step "rebuild font cache"
run fc-cache -f "$FONT_DIR"

# Verify, rather than assume. fc-match happily returns a substitute font and
# reports success, so it cannot answer "is this font present" -- match on the
# family list instead, and check the icon range separately.
if fc-list : family 2>/dev/null | tr ',' '\n' | grep -qix "Geist"; then
    ok "Geist present"
else
    warn "Geist still not visible to fontconfig"
fi

if fc-list ':charset=F0425' family 2>/dev/null | grep -qi nerd; then
    ok "Nerd Font icon range intact (U+F0425)"
else
    warn "no font carries U+F0425 — waybar/rofi icons will render as boxes"
fi
