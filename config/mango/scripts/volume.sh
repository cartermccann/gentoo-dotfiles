#!/usr/bin/env bash
# Volume control via PipeWire's wpctl
sink="@DEFAULT_AUDIO_SINK@"
case "$1" in
    up)   wpctl set-volume -l 1.5 "$sink" 5%+ ;;
    down) wpctl set-volume "$sink" 5%- ;;
    mute) wpctl set-mute "$sink" toggle ;;
    *)    echo "usage: volume.sh {up|down|mute}" >&2; exit 1 ;;
esac
