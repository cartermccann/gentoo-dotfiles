#!/usr/bin/env bash
# Phase: devtools — developer CLIs that are not part of the desktop.
#
# Split from 30-ai-tools (agent CLIs) and from 10-packages (the system and its
# terminal toolset) because these are the tools client work needs — deploy,
# cloud, API and container CLIs — and they come from four different places.
# Which place, and why it is not just "emerge it", is the point of this file:
# only three of these have an ebuild at all.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

LOG="$HOME/.cache/atlas-devtools.log"; mkdir -p "$(dirname "$LOG")"

# ── portage ────────────────────────────────────────────────────
# Both GURU packages need a keyword line (GURU never stabilises anything);
# awscli-bin over awscli deliberately — the source build drags in a large
# python dependency set to produce the same binary.
step "portage CLIs"
PORTAGE_CLIS=(
    dev-util/stripe-cli      # GURU
    app-admin/awscli-bin
    dev-util/bruno-bin       # GURU — API client, the Electron repack
)
for pkg in "${PORTAGE_CLIS[@]}"; do
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] emerge $pkg"; continue; fi
    if qlist -I "$pkg" >/dev/null 2>&1; then ok "$pkg (already)"; continue; fi
    echo "### $pkg" >> "$LOG"
    if as_root emerge --noreplace --quiet "$pkg" >>"$LOG" 2>&1; then ok "$pkg"
    else warn "$pkg failed (see $LOG)"; fi
done

# ── npm globals ────────────────────────────────────────────────
# Pinned to the versions kronos runs. Unpinned installs are how two machines
# quietly diverge on the tool that deploys production.
step "npm CLIs"
NPM_CLIS=(
    vercel@56.5.0
    wrangler@4.106.0
    playwright@1.61.1
    ccusage
    ccstatusline
)
if ! have npm; then
    warn "npm missing — run ./install.sh packages"
else
    for pkg in "${NPM_CLIS[@]}"; do
        name="${pkg%@*}"
        if [ "$DRY_RUN" = "1" ]; then info "[dry-run] npm i -g $pkg"; continue; fi
        if npm ls -g --depth=0 "$name" >/dev/null 2>&1; then ok "$name (already)"; continue; fi
        if npm install -g "$pkg" >>"$LOG" 2>&1; then ok "$pkg"
        else warn "$pkg failed (see $LOG)"; fi
    done
fi

# ── uv tools ───────────────────────────────────────────────────
# headroom-ai needs two things right or it installs and then does not run:
#   --python 3.13  — 3.14 has no wheel, so uv falls back to a Rust source
#                    build that segfaults the linker on this machine
#   [all]          — the bare package omits fastapi/uvicorn, so every entry
#                    point dies at import on "from fastapi import Request".
#                    Not just the proxy: the CLI imports the proxy module, so
#                    even `headroom --version` tracebacks. This is what kronos
#                    installed (uv-receipt.toml: extras = ["all"]).
step "uv tools"
if ! have uv; then
    warn "uv missing — run ./install.sh ai"
else
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] uv tool install headroom-ai[all] --python 3.13; uv tool install posting"
    else
        # `have headroom` is not a sufficient check: a broken install still
        # leaves the shim on PATH. Verify it actually executes.
        if headroom --version >/dev/null 2>&1; then ok "headroom-ai (already)"
        elif uv tool install --force --python 3.13 "headroom-ai[all]" >>"$LOG" 2>&1; then
            ok "headroom-ai[all]"
        else warn "headroom-ai failed (see $LOG)"; fi
        have posting || uv tool install posting >>"$LOG" 2>&1 \
            && ok "posting" || warn "posting failed (see $LOG)"
    fi
fi

# ── go install ─────────────────────────────────────────────────
# lazydocker has no ebuild in ::gentoo or ::guru. Same situation as gum in
# 10-packages, so same treatment.
step "lazydocker (via go install — no ebuild exists)"
if have lazydocker; then ok "lazydocker (already)"
elif [ "$DRY_RUN" = "1" ]; then info "[dry-run] go install lazydocker"
elif have go; then
    if go install github.com/jesseduffield/lazydocker@latest >>"$LOG" 2>&1; then
        ok "lazydocker -> $(go env GOBIN 2>/dev/null || echo "$HOME/go/bin")"
    else warn "lazydocker failed (see $LOG)"; fi
else warn "go missing — skipping lazydocker"; fi

# ── upstream installers ────────────────────────────────────────
# flyctl and gcloud ship their own installers and self-update. Neither is
# packaged for Gentoo, and both are the vendors' supported path. They install
# under $HOME, so no root is involved.
step "flyctl"
if have flyctl || [ -x "$HOME/.fly/bin/flyctl" ]; then ok "flyctl (already)"
elif [ "$DRY_RUN" = "1" ]; then info "[dry-run] curl -L https://fly.io/install.sh | sh"
else
    if curl -fsSL https://fly.io/install.sh | sh >>"$LOG" 2>&1; then
        ok "flyctl -> ~/.fly/bin"
    else warn "flyctl install failed (see $LOG)"; fi
fi

# gcloud goes in ~/apps because it is a self-updating vendor bundle you run,
# not source you edit — the same rule that put the Codex bundle there.
step "google-cloud-sdk"
GCLOUD_DIR="$HOME/apps/google-cloud-sdk"
if [ -x "$GCLOUD_DIR/bin/gcloud" ]; then ok "gcloud (already)"
elif [ "$DRY_RUN" = "1" ]; then info "[dry-run] fetch google-cloud-cli tarball -> ~/apps"
else
    tmp="$(mktemp -d)"
    url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz"
    if curl -fsSL "$url" -o "$tmp/gcloud.tgz" >>"$LOG" 2>&1; then
        mkdir -p "$HOME/apps"
        tar -xzf "$tmp/gcloud.tgz" -C "$HOME/apps" >>"$LOG" 2>&1
        # --usage-reporting=false: this is a work machine, not a telemetry
        # sample. --path-update=false: PATH is set in config/fish/config.fish,
        # and letting the installer append to shell rc files would put the same
        # entry in two places that then disagree.
        "$GCLOUD_DIR/install.sh" --quiet --usage-reporting=false \
            --path-update=false --command-completion=false >>"$LOG" 2>&1 \
            && ok "gcloud -> ~/apps/google-cloud-sdk" \
            || warn "gcloud install script failed (see $LOG)"
    else
        warn "gcloud download failed (see $LOG)"
    fi
    rm -rf "$tmp"
fi

# ── summary ────────────────────────────────────────────────────
# Checks the install locations, not just $PATH. This phase runs under bash,
# while the PATH entries for the $HOME-installed CLIs are set in
# config/fish/config.fish — so a PATH-only check reports flyctl and gcloud
# missing immediately after successfully installing them.
step "summary"
check_cli() {   # name [extra path to try]
    if command -v "$1" >/dev/null 2>&1; then ok "$1"
    elif [ -n "${2:-}" ] && [ -x "$2" ]; then ok "$1 (at ${2/#$HOME/\~}, on PATH in fish)"
    else warn "$1 MISSING"; fi
}
for c in vercel wrangler playwright ccusage ccstatusline stripe bruno \
         headroom posting; do check_cli "$c"; done
check_cli aws        "/usr/bin/aws"
check_cli lazydocker "$(go env GOPATH 2>/dev/null || echo "$HOME/go")/bin/lazydocker"
check_cli flyctl     "$HOME/.fly/bin/flyctl"
check_cli gcloud     "$GCLOUD_DIR/bin/gcloud"

ok "devtools phase complete"
