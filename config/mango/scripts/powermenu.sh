#!/usr/bin/env bash
# rofi power menu — session actions via loginctl (elogind).
# Reached from Super+Shift+Escape and from the waybar power chip.
#
# The icons are Nerd Font Material Design glyphs. They are easy to lose: an
# editor or a here-doc that mangles UTF-8 silently turns them into spaces, and
# the menu still "works", just with a blank column. If they ever vanish, check
# the codepoints named below rather than retyping them from a font preview.
#   󰌾=U+F033E lock  󰍃=U+F0343 logout  󰒲=U+F04B2 sleep
#   󰜉=U+F0709 restart  󰐥=U+F0425 power
opt="$(printf '󰌾  Lock\n󰍃  Logout\n󰒲  Suspend\n󰜉  Reboot\n󰐥  Shutdown' \
  | rofi -dmenu -i -p "power" -theme-str '* { width: 320px; }' \
  | sed 's/^[^A-Za-z]*//')"
case "$opt" in
    Lock)     swaylock -f ;;
    Logout)   pkill -x mango ;;
    Suspend)  loginctl suspend ;;
    Reboot)   loginctl reboot ;;
    Shutdown) loginctl poweroff ;;
esac
