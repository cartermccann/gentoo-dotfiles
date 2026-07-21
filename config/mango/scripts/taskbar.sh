#!/usr/bin/env bash
# Waybar custom module: open windows grouped by tag, in tag order.
#
# waybar's wlr/taskbar cannot do this. It uses wlr-foreign-toplevel, which has
# no concept of tags, and offers only sort-by-app-id / sort-by-number /
# active-first. waybar's dwl/tags module is not compiled in, and mango does not
# implement the dwl IPC anyway (zdwl_ipc refs: 0), so it could not work either.
# mango's own IPC does report each client's tag, so we render it ourselves.
set -uo pipefail

command -v mmsg >/dev/null 2>&1 || { echo '{"text":""}'; exit 0; }
command -v jq   >/dev/null 2>&1 || { echo '{"text":""}'; exit 0; }

# waybar inherits MANGO_INSTANCE_SIGNATURE from mango. If it is missing we are
# not inside a mango session, so render nothing rather than erroring.
[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] || { echo '{"text":""}'; exit 0; }

clients=$(mmsg get all-clients 2>/dev/null) || { echo '{"text":""}'; exit 0; }
tags=$(mmsg get all-tags 2>/dev/null)       || { echo '{"text":""}'; exit 0; }

# Palette from the active theme so the tag numbers track atlas-theme.
theme=$(cat "$HOME/.local/state/atlas/current-theme" 2>/dev/null || echo cobalt)
pal="$HOME/gentoo-dotfiles/themes/$theme/colors.sh"
accent=$(sed -n 's/^.*ACCENT=\([0-9a-fA-F]\{6\}\).*$/\1/p' "$pal" 2>/dev/null | head -1)
subtext=$(sed -n 's/^.*SUBTEXT=\([0-9a-fA-F]\{6\}\).*$/\1/p' "$pal" 2>/dev/null | head -1)
: "${accent:=3b6bff}"; : "${subtext:=8b93a4}"

jq -rn --argjson c "$clients" --argjson t "$tags" \
       --arg accent "$accent" --arg subtext "$subtext" '
  # Which tag index is currently active?
  ($t.all_tags[0].tags // []) as $tagdefs
  | ($tagdefs | map(select(.is_active)) | map(.index) | first) as $active
  # Group clients by their first tag, then order by tag then window id.
  | ($c.clients // [])
    | map({ tag: (.tags[0] // 0), appid: .appid, title: .title,
            id: .id, focused: .is_focused })
    | sort_by(.tag, .id)
    | group_by(.tag)
    | map(
        (.[0].tag) as $tag
        | (if $tag == $active then $accent else $subtext end) as $col
        # Strip the reverse-DNS prefix: com.mitchellh.ghostty -> ghostty
        | (map(
            (.appid | split(".") | last | ascii_downcase) as $name
            | if .focused then "<b>\($name)</b>" else $name end
          ) | join(" ")) as $apps
        | "<span color=\"#\($col)\"><b>\($tag)</b></span> \($apps)"
      )
    | join("   ")
  | { text: ., tooltip: "" }
  | @json
'
