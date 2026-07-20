#!/usr/bin/env python3
"""Transcribe a 16 kHz mono WAV with the Parakeet TDT model via sherpa-onnx.

Usage: transcribe.py <model_dir> <wav_path>   ->   prints recognized text
Runs inside the parakeet-dictation venv (has sherpa-onnx, soundfile, numpy).
"""
import sys
import sherpa_onnx
import soundfile as sf


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: transcribe.py <model_dir> <wav>", file=sys.stderr)
        return 2
    model_dir, wav = sys.argv[1], sys.argv[2]

    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=f"{model_dir}/encoder.int8.onnx",
        decoder=f"{model_dir}/decoder.int8.onnx",
        joiner=f"{model_dir}/joiner.int8.onnx",
        tokens=f"{model_dir}/tokens.txt",
        num_threads=4,
        model_type="nemo_transducer",
    )

    audio, sample_rate = sf.read(wav, dtype="float32", always_2d=False)
    if audio.ndim > 1:  # stereo -> mono
        audio = audio[:, 0]

    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, audio)
    recognizer.decode_stream(stream)
    print(stream.result.text.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
