#!/usr/bin/env bash
# Screenshot via grim + slurp, saved to ~/Pictures/Screenshots and copied to clipboard
set -u
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
f="$dir/shot-$(date +%Y%m%d-%H%M%S).png"

case "${1:-region}" in
    region) grim -g "$(slurp -b 1e1e2e55 -c 89b4faff)" "$f" ;;
    full)   grim "$f" ;;
    *)      echo "usage: screenshot.sh {region|full}" >&2; exit 1 ;;
esac

if [ -f "$f" ]; then
    wl-copy < "$f"
    command -v notify-send >/dev/null 2>&1 && notify-send "Screenshot" "Saved & copied: $(basename "$f")"
fi
