#!/usr/bin/env bash
# T3 Code desktop launcher. Ours, not upstream's — the extracted AppImage
# payload ships only AppRun and the bare t3code binary, no launcher.
#
# The ozone flags are not optional on this machine: MangoWM is Wayland and
# there is no Xwayland running here, so an X11 default is not a slower window,
# it is no window at all. T3CODE_X11=1 drops them, for the case where you have
# deliberately started an Xwayland and want to test against it.
#
# Sandbox: deliberately NOT passing --no-sandbox. AppRun probes for
# unprivileged user namespaces with `unshare -Ur true` and adds the flag itself
# when they are unavailable, so passing it here would disable the sandbox on a
# machine that can support it. atlas has userns enabled, so Chromium uses the
# namespace sandbox and chrome-sandbox does not need to be setuid root — which
# is what lets this whole bundle live in $HOME with no privileged step.
#
# Resolves its own directory rather than hardcoding ~/apps/t3code, so the
# bundle can be moved without editing this file. readlink -f first, because
# ~/.local/bin/t3code is a symlink to this script: dirname on the unresolved
# $BASH_SOURCE yields ~/.local/bin and looks for AppRun there.
set -uo pipefail
exec_args=(--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations)
[[ -n "${T3CODE_X11:-}" ]] && exec_args=()
exec "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/AppRun" "${exec_args[@]}" "$@"
