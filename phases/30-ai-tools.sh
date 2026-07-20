#!/usr/bin/env bash
# Phase: ai — AI coding CLIs + JS/Python runtimes not cleanly in the tree.
set -uo pipefail
: "${REPO_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/lib/common.sh"

# ── npm global prefix in $HOME (no root needed) ────────────────
step "npm global prefix (~/.npm-global)"
if have npm; then
    run mkdir -p "$HOME/.npm-global"
    run npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    ok "npm prefix set (ensure ~/.npm-global/bin is on PATH — the fish config does this)"
else
    warn "npm not found — run the packages phase first (installs nodejs)"
fi

npm_g() {
    have npm || return 1
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] npm i -g $1"; return 0; fi
    npm install -g "$1" >/dev/null 2>&1 && ok "$1" || { warn "npm failed: $1"; return 1; }
}

curl_sh() { # name url [shell]
    local name=$1 url=$2 sh=${3:-bash}
    if [ "$DRY_RUN" = "1" ]; then info "[dry-run] curl $url | $sh"; return 0; fi
    if curl -fsSL "$url" | "$sh" >/dev/null 2>&1; then ok "$name"; else warn "installer failed: $name"; fi
}

step "AI coding CLIs"
npm_g "@anthropic-ai/claude-code"
npm_g "@openai/codex"
curl_sh opencode "https://opencode.ai/install"

step "JS / Python runtimes"
curl_sh bun "https://bun.sh/install"
curl_sh deno "https://deno.land/install.sh" sh
curl_sh uv "https://astral.sh/uv/install.sh" sh
if have corepack; then run_root corepack enable || npm_g pnpm; else npm_g pnpm; fi

# ── herdr (Carter's agent workspace manager) ───────────────────
step "herdr"
if have cargo; then
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] cargo install --git https://github.com/ogulcancelik/herdr --tag v0.7.1"
    elif cargo install --git https://github.com/ogulcancelik/herdr --tag v0.7.1 >/dev/null 2>&1; then
        ok "herdr (cargo)"
    else
        warn "herdr cargo build failed — grab a prebuilt binary from"
        warn "  https://github.com/ogulcancelik/herdr/releases/tag/v0.7.1  → ~/.local/bin/"
    fi
else
    warn "cargo not found (rust-bin) — run packages phase, then re-run: ./install.sh ai"
fi

ok "ai phase complete"
