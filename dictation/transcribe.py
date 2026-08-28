#!/usr/bin/env python3
"""Transcribe a WAV file with a sherpa-onnx Parakeet TDT model. Prints the text.

Called by toggle-dictation.sh as:  python transcribe.py <model-dir> <wav>

This file was missing entirely until 2026-08-28, which is why dictation always
reported "No transcription": toggle-dictation.sh swallows the failure with
`2>/dev/null || true`, so an absent script looked identical to silence.

Parakeet TDT is a NeMo transducer, so model_type must be "nemo_transducer";
the default "transducer" expects Icefall-style models and produces garbage or
an error on these weights.
"""
import sys
import numpy as np
import soundfile as sf
import sherpa_onnx


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <model-dir> <wav>", file=sys.stderr)
        return 2
    model_dir, wav_path = sys.argv[1], sys.argv[2]

    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=f"{model_dir}/encoder.int8.onnx",
        decoder=f"{model_dir}/decoder.int8.onnx",
        joiner=f"{model_dir}/joiner.int8.onnx",
        tokens=f"{model_dir}/tokens.txt",
        model_type="nemo_transducer",
        num_threads=4,
        sample_rate=16000,
        feature_dim=80,
        decoding_method="greedy_search",
    )

    samples, sample_rate = sf.read(wav_path, dtype="float32", always_2d=False)
    if samples.ndim > 1:                 # mixdown, in case the recorder gave stereo
        samples = samples.mean(axis=1)
    if samples.size == 0:
        return 1

    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, np.ascontiguousarray(samples))
    recognizer.decode_stream(stream)

    text = (stream.result.text or "").strip()
    if not text:
        return 1
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
