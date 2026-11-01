"""Synthesises the text "voice": the soft sound played for each typed letter of dialogue.

  assets/audio/text_wood_0..2.wav   marimba-like wooden "tok", three slightly different pitches

Run from the repo root:  python tools/audio/make_text_voice.py   (no packages needed)
"""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"
SR = 22050


def voice_wood(f):
    """Marimba-like tok: sine plus a quiet 4x partial, very fast decay."""
    n = int(0.06 * SR)
    return [(math.sin(2 * math.pi * f * i / SR) + 0.25 * math.sin(2 * math.pi * f * 4 * i / SR) * math.exp(-i / SR * 160))
            * min(1, i / (0.0015 * SR)) * math.exp(-i / SR * 70) * 0.55 for i in range(n)]


def save(path, samples, peak=0.7):
    scale = peak / max(1e-9, max(abs(s) for s in samples))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print(path.relative_to(ROOT))


def main():
    for i, f in enumerate((392, 415, 440)):
        save(OUT / f"text_wood_{i}.wav", voice_wood(f))


if __name__ == "__main__":
    main()
