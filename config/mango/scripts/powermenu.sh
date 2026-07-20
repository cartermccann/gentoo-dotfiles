#!/usr/bin/env bash
# rofi power menu — power actions via loginctl (elogind)
opt="$(printf '  Lock\n  Logout\n  Suspend\n  Reboot\n  Shutdown' \
  | rofi -dmenu -i -p "power" -theme-str '* { width: 300px; }' \
  | sed 's/^[^A-Za-z]*//')"
case "$opt" in
    Lock)     swaylock -f ;;
    Logout)   pkill -x mango ;;
    Suspend)  loginctl suspend ;;
    Reboot)   loginctl reboot ;;
    Shutdown) loginctl poweroff ;;
esac
