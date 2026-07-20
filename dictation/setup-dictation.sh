#!/usr/bin/env bash
# One-time setup for Parakeet dictation: a uv venv with sherpa-onnx + the
# Parakeet TDT 0.6B v2 (int8) NeMo model. Idempotent; safe to re-run.
set -euo pipefail

SHARE="$HOME/.local/share/parakeet-dictation"
MODEL_DIR="$SHARE/sherpa-model"
VENV="$SHARE/venv"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2"
MODEL_TOP="sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"

mkdir -p "$SHARE"

# ── Python env (sherpa-onnx via uv) ────────────────────────────
if [ ! -x "$VENV/bin/python" ]; then
    command -v uv >/dev/null || { echo "uv not found — run './install.sh ai' first"; exit 1; }
    echo "Creating venv + installing sherpa-onnx…"
    uv venv "$VENV" --python 3.13
    uv pip install --python "$VENV/bin/python" sherpa-onnx soundfile numpy
fi

# ── Model (~480 MB) ────────────────────────────────────────────
if [ ! -f "$MODEL_DIR/encoder.int8.onnx" ]; then
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    echo "Downloading Parakeet TDT 0.6B v2 int8 (~480 MB)…"
    curl -L --fail --progress-bar -o "$TMP/model.tar.bz2" "$MODEL_URL"
    echo "Extracting…"
    tar -xjf "$TMP/model.tar.bz2" -C "$TMP"
    mv "$TMP/$MODEL_TOP" "$MODEL_DIR"
fi

echo "Dictation ready — model at $MODEL_DIR"
