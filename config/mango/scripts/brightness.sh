#!/usr/bin/env bash
# Backlight control via brightnessctl
case "$1" in
    up)   brightnessctl set 5%+ ;;
    down) brightnessctl set 5%- ;;
    *)    echo "usage: brightness.sh {up|down}" >&2; exit 1 ;;
esac
