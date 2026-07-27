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

    # ── 3. ELF interpreter and RPATH ───────────────────────────
    # The deepest Nix assumption in the bundle, and the one that actually kept
    # the app from starting at all until 2026-07-27. Every compiled binary here
    # names an absolute /nix/store loader in its ELF INTERP header. That path
    # does not exist on Gentoo, so the kernel refuses the exec and bash reports
    #
    #     .../electron: cannot execute: required file not found
    #
    # which reads like a missing *file* but means a missing *loader* — the file
    # named in the error is right there and executable.
    #
    # RPATHs are the same story one level down: they name store directories for
    # glibc, gcc, and the GTK/X stack, every one of which Gentoo already has on
    # the default linker path. $ORIGIN replaces them, so a binary keeps finding
    # the libraries shipped beside it (electron's own libffmpeg.so and friends)
    # and finds everything else the normal way.
    #
    # Note that ldd cannot diagnose any of this — it runs the binary's own
    # interpreter, so a missing loader makes it fail wholesale instead of
    # naming a library. That is why step 6 checks INTERP before it checks libs.
    LOADER=/lib64/ld-linux-x86-64.so.2
    if ! command -v patchelf >/dev/null 2>&1; then
        err "patchelf missing — it is in phases/10-packages.sh; run ./install.sh packages"
    elif [ ! -e "$LOADER" ]; then
        err "system ELF loader not found at $LOADER"
    else
        # Candidates: anything executable, plus shared objects and Node native
        # addons (which have no exec bit but do carry RPATHs). The *.before-*
        # files are the bundle's own pre-patch backups — never touch them.
        interp_n=0 rpath_n=0
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            case "$f" in *.before-*) continue;; esac

            # INTERP: only executables have one; patchelf errors out otherwise.
            if patchelf --print-interpreter "$f" 2>/dev/null | grep -q '/nix/store'; then
                run patchelf --set-interpreter "$LOADER" "$f" && interp_n=$((interp_n + 1))
            fi
            # RPATH: applies to executables and libraries alike.
            if patchelf --print-rpath "$f" 2>/dev/null | grep -q '/nix/store'; then
                run patchelf --set-rpath '$ORIGIN' "$f" && rpath_n=$((rpath_n + 1))
            fi
        done <<EOF
$(find "$CODEX" \( -type f -executable -o -name '*.so' -o -name '*.so.*' -o -name '*.node' \) 2>/dev/null)
EOF

        if [ "$interp_n" -gt 0 ] || [ "$rpath_n" -gt 0 ]; then
            ok "de-Nixed ELF headers: $interp_n interpreter(s), $rpath_n rpath(s) → \$ORIGIN"
        else
            ok "ELF interpreters and rpaths already portable"
        fi
    fi

    # ── 4. Node runtime ────────────────────────────────────────
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

    # ── 5. Bundled plugin scripts ──────────────────────────────
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

    # ── 6. Can it actually link? ───────────────────────────────
    # Empirical, not assumed. Anything still missing here is a package to add
    # to phases/10-packages.sh, not something to paper over at runtime.
    #
    # Check the interpreter FIRST. ldd works by invoking the binary's own
    # loader, so when INTERP is dangling it fails as a whole and prints no
    # "not found" line at all — and a grep for "not found" over no output
    # matches nothing, which this step used to report as success. That false
    # pass is exactly how a completely unlaunchable app showed six green ticks.
    step "Codex desktop / library check"
    interp=$(patchelf --print-interpreter "$CODEX/electron" 2>/dev/null || true)
    if [ ! -e "${interp:-/nonexistent}" ]; then
        err "electron's ELF interpreter is missing: ${interp:-<none>}"
        warn "step 3 should have rewritten it — check that patchelf is installed"
    else
        missing=$(cd "$CODEX" && LD_LIBRARY_PATH="$CODEX" ldd ./electron 2>/dev/null \
                  | grep 'not found' | awk '{print $1}' | sort -u)
        if [ -n "$missing" ]; then
            err "electron is missing shared libraries:"
            printf '      %s\n' $missing
            warn "add the providing package to phases/10-packages.sh, then re-run packages"
        else
            ok "electron links: interpreter $interp, all libraries resolve"
        fi
    fi

    # ── 7. Launcher entry ──────────────────────────────────────
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
# The kit's native pieces ship linux-x64 glibc prebuilds, so a copy from
# another glibc x86-64 machine runs as-is — there is no need to rebuild the
# Input app on Gentoo, which is the expensive path the input-linux README
# describes.
#
# What DOES bite: npm hoisted several of the kit's dependencies up to the Input
# app's top-level node_modules, so copying the kit directory alone yields a
# package that cannot resolve its own requires. The kit externalises exactly
# three modules (node-hid, serialport, fs); serialport is nested inside the kit
# already, and the rest of the closure is KIT_HOISTED_DEPS below. Copy those
# from the same top-level node_modules alongside the kit.
step "Work Louder device kit"
KIT_DIR="$APPS/vendor/wl-device-kit"
KIT="$KIT_DIR/dist/index.js"
KIT_HOISTED_DEPS=(node-hid pkg-prebuilds @serialport/binding-mock @serialport/bindings-interface)

if [ ! -f "$KIT" ]; then
    warn "missing — the Codex Micro bridge cannot run without it"
    info "copy it from a machine with Work Louder Input installed:"
    info "  NM=<host>:~/projects/input-linux/input-app-<ver>/node_modules"
    info "  rsync -a \$NM/@worklouder/wl-device-kit/ ~/apps/vendor/wl-device-kit/"
    info "  rsync -aR \$NM/./{${KIT_HOISTED_DEPS[*]}} ~/apps/vendor/wl-device-kit/node_modules/"
else
    ok "${KIT/#$HOME/\~}"
    kit_missing=()
    for dep in "${KIT_HOISTED_DEPS[@]}"; do
        [ -d "$KIT_DIR/node_modules/$dep" ] || kit_missing+=("$dep")
    done
    if [ ${#kit_missing[@]} -gt 0 ]; then
        err "kit is missing hoisted dependencies: ${kit_missing[*]}"
        info "copy each from the Input app's top-level node_modules into"
        info "  ~/apps/vendor/wl-device-kit/node_modules/"
    else
        # Cheap and worth it: resolution failures here surface as a service
        # that crash-loops under s6 rather than as an error you see directly.
        if [ "${DRY_RUN:-0}" = "1" ]; then
            info "[dry-run] verify the kit loads"
        elif timeout 20 node -e "require('$KIT')" >/dev/null 2>&1; then
            ok "kit loads (all ${#KIT_HOISTED_DEPS[@]} hoisted deps resolve)"
        else
            err "kit is present but fails to load — run for the reason:"
            info "  node -e \"require('$KIT')\""
        fi
    fi
fi

step "micro-herdr checkout"
if [ -d "$HOME/projects/micro-herdr" ]; then
    ok "~/projects/micro-herdr"
else
    warn "missing — services/micro-herdr and micro-reconnect will fail to start"
    info "  git clone https://github.com/cartermccann/micro-herdr ~/projects/micro-herdr"
fi

ok "vendored phase complete"
