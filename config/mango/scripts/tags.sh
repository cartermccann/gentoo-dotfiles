#!/usr/bin/env bash
# Waybar custom module: workspace (tag) strip for mango.
#
# Companion to wlr/taskbar. wlr/taskbar draws the REAL app icons but is built
# on wlr-foreign-toplevel, which has no concept of tags and therefore cannot be
# ordered by workspace. Rather than trade real icons for monochrome glyphs,
# this strip carries the workspace information alongside them.
#
# All nine tags always render, so positions stay stable and countable:
#   ●  active tag        (accent)
#   ●  has windows       (subtext)
#   ·  empty             (faint)
set -uo pipefail

command -v mmsg >/dev/null 2>&1 || { echo '{"text":""}'; exit 0; }
command -v jq   >/dev/null 2>&1 || { echo '{"text":""}'; exit 0; }
[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] || { echo '{"text":""}'; exit 0; }

tags=$(mmsg get all-tags 2>/dev/null) || { echo '{"text":""}'; exit 0; }

theme=$(cat "$HOME/.local/state/atlas/current-theme" 2>/dev/null || echo cobalt)
pal="$HOME/gentoo-dotfiles/themes/$theme/colors.sh"
accent=$(sed -n 's/^.*ACCENT=\([0-9a-fA-F]\{6\}\).*$/\1/p' "$pal" 2>/dev/null | head -1)
subtext=$(sed -n 's/^.*SUBTEXT=\([0-9a-fA-F]\{6\}\).*$/\1/p' "$pal" 2>/dev/null | head -1)
: "${accent:=3b6bff}"; : "${subtext:=8b93a4}"

jq -rn --argjson t "$tags" --arg accent "$accent" --arg subtext "$subtext" '
  ($t.all_tags[0].tags // []) as $tags
  | ( $tags
      | map(
          if .is_active then
            "<span color=\"#\($accent)\">●</span>"
          elif (.client_count // 0) > 0 then
            "<span color=\"#\($subtext)\">●</span>"
          else
            "<span color=\"#\($subtext)\" alpha=\"30%\">·</span>"
          end
        )
      | join(" ")
    ) as $strip
  | ( $tags | map(select((.client_count // 0) > 0))
            | map("\(.index): \(.client_count)") | join("\n") ) as $tip
  | { text: $strip, tooltip: (if $tip == "" then "no windows" else $tip end) }
  | @json
'
