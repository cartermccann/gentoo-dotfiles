#!/usr/bin/env bash
# Toggle Parakeet dictation: 1st press records, 2nd press transcribes + types.
# Wayland-native (wtype). First run auto-downloads the model + venv.
set -uo pipefail

SELF="$(readlink -f "$0")"; DIR="$(dirname "$SELF")"
SHARE="$HOME/.local/share/parakeet-dictation"
MODEL_DIR="$SHARE/sherpa-model"; VENV="$SHARE/venv"
STATE="$HOME/.local/state/parakeet-dictation"; mkdir -p "$STATE"
WAV="$STATE/recording.wav"; RECPID="$STATE/recorder.pid"

notify() { notify-send -i audio-input-microphone-symbolic -t 2000 "Dictation" "$1" 2>/dev/null || true; }

# ── First-run setup ────────────────────────────────────────────
if [ ! -f "$MODEL_DIR/encoder.int8.onnx" ] || [ ! -x "$VENV/bin/python" ]; then
    notify "Setting up (first run, ~480 MB)…"
    "$DIR/setup-dictation.sh" || { notify "Setup failed"; exit 1; }
fi

# ── Clear stale recorder state ─────────────────────────────────
if [ -f "$RECPID" ]; then
    p="$(cat "$RECPID" 2>/dev/null || true)"
    if [ -z "$p" ] || ! kill -0 "$p" 2>/dev/null; then rm -f "$RECPID" "$WAV"; fi
fi

if [ -f "$RECPID" ] && kill -0 "$(cat "$RECPID")" 2>/dev/null; then
    # ── Stop → transcribe → type ──
    pid="$(cat "$RECPID")"
    kill -INT "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    rm -f "$RECPID"
    notify "Transcribing…"

    TEXT="$("$VENV/bin/python" "$DIR/transcribe.py" "$MODEL_DIR" "$WAV" 2>/dev/null || true)"

    if [ -n "$TEXT" ]; then
        if command -v wtype >/dev/null 2>&1; then
            wtype -- "$TEXT"
        else
            printf '%s' "$TEXT" | wl-copy && notify "Copied (install wtype to type)"
        fi
        notify "Done"
    else
        notify "No transcription"
    fi
else
    # ── Start recording ──
    pw-record --rate 16000 --channels 1 --format s16 "$WAV" &
    echo $! > "$RECPID"
    notify "Listening…"
fi
