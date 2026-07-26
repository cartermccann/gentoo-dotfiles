#!/usr/bin/env bash
# Phase: vendored — prebuilt applications that no package manager ships.
#
# The third case after 25-apps (Gentoo has an ebuild) and 20-flatpaks (Flathub
# has it). These are binaries you obtained yourself and keep in ~/apps: nothing
# updates them, nothing else depends on them, and they are not in this repo
# because they are large opaque blobs. What IS in this repo is everything
# needed to make them run here — which for a bundle built on NixOS means
# unpicking its assumptions about where libraries live.
#
# This phase is idempotent and reports what it finds rather than assuming.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

APPS="$HOME/apps"

# ═══ Codex / ChatGPT desktop ═══════════════════════════════════
CODEX="$APPS/codex-desktop"

step "Codex desktop"
if [ ! -d "$CODEX" ]; then
    warn "not present at ${CODEX/#$HOME/\~} — skipping"
    info "it is an unpacked Electron bundle, copied from the machine that built it:"
    info "  rsync -a --exclude='*.before-*' kronos:~/apps/codex-desktop/ ~/apps/codex-desktop/"
else
    # ── 1. Interpreter ─────────────────────────────────────────
    # The launcher was generated on NixOS, so its shebang is an absolute
    # /nix/store path that does not exist here. Nothing else about the script
    # is Nix-specific.
    if head -1 "$CODEX/start.sh" | grep -q '/nix/store'; then
        run sed -i '1s|.*|#!/usr/bin/env bash|' "$CODEX/start.sh"
        ok "start.sh shebang → /usr/bin/env bash"
    else
        ok "start.sh shebang already portable"
    fi

    # ── 2. Library path ────────────────────────────────────────
    # NixOS has no global library directory, so the bundle carried an absolute
    # LD_LIBRARY_PATH naming ~35 store paths. On Gentoo every one of those is
    # already on the default linker path and the line is actively harmful:
    # it points at directories that do not exist.
    #
    # What genuinely does need help is the bundle's OWN libraries
    # (libffmpeg.so, libEGL.so, libGLESv2.so, libvulkan.so.1), because
    # Electron dlopen()s several of them by bare name rather than through its
    # rpath. So the replacement is the app directory and nothing else.
    if grep -q '^export LD_LIBRARY_PATH="/nix/store' "$CODEX/start.sh"; then
        run sed -i \
          -e 's|^# NixOS Electron library path for dlopen()ed GL/EGL libraries\.$|# Gentoo: system libraries are already on the default linker path. Only the|' \
          -e 's|^# Codex Micro Linux HID runtime: /nix/store.*$|# bundle'"'"'s own libs need help — Electron dlopen()s some by bare name.|' \
          -e 's|^export LD_LIBRARY_PATH="/nix/store.*$|export LD_LIBRARY_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" \&\& pwd)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"|' \
          "$CODEX/start.sh"
        ok "LD_LIBRARY_PATH → the app directory (was ~35 /nix/store paths)"
    else
        ok "LD_LIBRARY_PATH already portable"
    fi

    # ── 3. Node runtime ────────────────────────────────────────
    # resources/node-runtime is a symlink to a nodejs derivation, used as a
    # PREFIX (the app reaches for $node-runtime/bin/node). On Gentoo that
    # prefix is /usr.
    if [ -L "$CODEX/resources/node-runtime" ] && \
       readlink "$CODEX/resources/node-runtime" | grep -q '/nix/store'; then
        run ln -sfn /usr "$CODEX/resources/node-runtime"
        ok "resources/node-runtime → /usr  ($(node --version 2>/dev/null || echo 'node missing!'))"
    else
        ok "node-runtime already portable"
    fi

    # ── 4. Bundled plugin scripts ──────────────────────────────
    # The bundled 'sites' plugin ships shell scripts whose shebangs were also
    # rewritten to the store. They only run when you use that plugin, which is
    # exactly why they would otherwise fail confusingly and much later.
    nixshebangs=$(grep -rl '^#!/nix/store' "$CODEX/resources/plugins" 2>/dev/null)
    if [ -n "$nixshebangs" ]; then
        n=$(printf '%s\n' "$nixshebangs" | wc -l)
        printf '%s\n' "$nixshebangs" | while read -r f; do
            [ -n "$f" ] && run sed -i '1s|.*|#!/usr/bin/env bash|' "$f"
        done
        ok "$n bundled plugin script(s) reshebanged"
    else
        ok "bundled plugin scripts already portable"
    fi

    # ── 5. Can it actually link? ───────────────────────────────
    # Empirical, not assumed. Anything still missing here is a package to add
    # to phases/10-packages.sh, not something to paper over at runtime.
    step "Codex desktop / library check"
    missing=$(cd "$CODEX" && LD_LIBRARY_PATH="$CODEX" ldd ./electron 2>/dev/null \
              | grep 'not found' | awk '{print $1}' | sort -u)
    if [ -n "$missing" ]; then
        err "electron is missing shared libraries:"
        printf '      %s\n' $missing
        warn "add the providing package to phases/10-packages.sh, then re-run packages"
    else
        ok "electron resolves every shared library"
    fi

    # ── 6. Launcher entry ──────────────────────────────────────
    # Rendered from share/vendored/*.in rather than tracked verbatim, because
    # the Exec/Icon lines need an absolute path that depends on $HOME.
    step "Codex desktop / launcher entry"
    run mkdir -p "$HOME/.local/share/applications"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        info "[dry-run] render codex-desktop.desktop"
    else
        sed "s|@APPDIR@|$CODEX|g" \
            "$REPO_DIR/share/vendored/codex-desktop.desktop.in" \
            > "$HOME/.local/share/applications/codex-desktop.desktop"
        ok "~/.local/share/applications/codex-desktop.desktop"
    fi
    run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# ═══ Work Louder device kit ════════════════════════════════════
# Proprietary, ships inside the Work Louder "Input" app, and is NOT
# redistributable — which is why micro-herdr asks you to supply it rather than
# bundling it. It lives under ~/apps/vendor for the same reason the Codex
# bundle does: it is a binary you obtained, not source you edit (docs/LAYOUT.md).
#
# The kit's native pieces (@serialport/bindings-cpp) ship linux-x64 glibc
# prebuilds, so the copy from another glibc x86-64 machine runs as-is; there is
# no need to rebuild the Input app on Gentoo.
step "Work Louder device kit"
KIT="$APPS/vendor/wl-device-kit/dist/index.js"
if [ -f "$KIT" ]; then
    ok "${KIT/#$HOME/\~}"
else
    warn "missing — the Codex Micro bridge cannot run without it"
    info "copy it from a machine with Work Louder Input installed:"
    info "  rsync -a <host>:.../node_modules/@worklouder/wl-device-kit/ ~/apps/vendor/wl-device-kit/"
fi

step "micro-herdr checkout"
if [ -d "$HOME/projects/micro-herdr" ]; then
    ok "~/projects/micro-herdr"
else
    warn "missing — services/micro-herdr and micro-reconnect will fail to start"
    info "  git clone https://github.com/cartermccann/micro-herdr ~/projects/micro-herdr"
fi

ok "vendored phase complete"
