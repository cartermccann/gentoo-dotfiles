#!/usr/bin/env bash
# Toggle wlsunset, mirroring kronos's hypr-night-toggle (SUPER+CTRL+N).
# wlsunset has no IPC, so toggling means starting/stopping the process.
set -u
if pgrep -x wlsunset >/dev/null 2>&1; then
    pkill -x wlsunset
    command -v notify-send >/dev/null 2>&1 && notify-send "Night light" "Off"
else
    # -t night temp, -T day temp. Same 4000K night value as kronos.
    wlsunset -t 4000 -T 6500 >/dev/null 2>&1 &
    command -v notify-send >/dev/null 2>&1 && notify-send "Night light" "On"
fi
