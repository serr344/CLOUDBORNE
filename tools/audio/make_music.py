"""Synthesises the intro theme (pure Python, no packages needed).

  assets/audio/theme_lullaby.wav   3/4 music-box lullaby, D major, 84 BPM, 32 bars (~69 s)

A bell (sine + decaying partials) plays the melody over a soft piano-ish "oom-pah-pah"
accompaniment; on the second pass a quiet bell doubles the tune an octave higher. Everything goes
through a small Schroeder reverb; the reverb tail is folded back onto the start, so it loops
without a seam.
Run from the repo root:  python tools/audio/make_music.py
"""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"
SR = 22050
TAU = 2 * math.pi
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name):
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTES[pitch] + (octave + 1) * 12 - 69) / 12)


def up(name, octaves=1):
    return name[:-1] + str(int(name[-1]) + octaves)


# --------------------------------------------------------------- instruments
def inst_bell(f, dur):
    n = int((dur + 0.9) * SR)
    out = []
    for i in range(n):
        t = i / SR
        v = (math.sin(TAU * f * t) + 0.45 * math.sin(TAU * 2 * f * t) * math.exp(-t * 7)
             + 0.2 * math.sin(TAU * 3.01 * f * t) * math.exp(-t * 12))
        env = min(1.0, t / 0.003) * math.exp(-t * 2.6)
        if t > dur:
            env *= max(0.0, 1 - (t - dur) / 0.9)
        out.append(v * env)
    return out


def inst_soft(f, dur):
    """Piano-ish: smooth triangle plus a little octave sine, struck then decaying."""
    n = int((dur + 0.4) * SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += f / SR
        p = ph % 1.0
        tri = 4 * abs(p - 0.5) - 1
        v = tri * 0.8 + 0.3 * math.sin(TAU * 2 * f * t) * math.exp(-t * 4)
        env = min(1.0, t / 0.005) * (0.25 + 0.75 * math.exp(-t * 3.2))
        if t > dur:
            env *= max(0.0, 1 - (t - dur) / 0.4)
        out.append(v * env)
    return out


INST = {"bell": inst_bell, "soft": inst_soft}


class Track:
    def __init__(self, seconds):
        self.loop_n = int(seconds * SR)
        self.buf = [0.0] * (self.loop_n + 4 * SR)

    def note(self, t, name_or_f, beats_sec, inst, vol):
        f = freq(name_or_f) if isinstance(name_or_f, str) else name_or_f
        samples = INST[inst](f, beats_sec)
        i0 = int(t * SR)
        buf = self.buf
        for k, v in enumerate(samples):
            j = i0 + k
            if j < len(buf):
                buf[j] += v * vol

    def render(self, wet=0.22, lowpass=0.6):
        x = self.buf
        # Schroeder reverb: 4 damped combs in parallel, then 2 allpasses
        combs = [558, 594, 638, 678]
        acc = [0.0] * len(x)
        for d in combs:
            line = [0.0] * d
            idx = 0
            lp = 0.0
            for i in range(len(x)):
                y = line[idx]
                lp = y * 0.7 + lp * 0.3
                line[idx] = x[i] + lp * 0.78
                idx = (idx + 1) % d
                acc[i] += y
        for d in (112, 278):
            line = [0.0] * d
            idx = 0
            for i in range(len(acc)):
                b = line[idx]
                y = -acc[i] * 0.5 + b
                line[idx] = acc[i] + b * 0.5
                idx = (idx + 1) % d
                acc[i] = y
        mix = [x[i] + acc[i] * wet / 4 for i in range(len(x))]
        out = mix[:self.loop_n]
        for i in range(self.loop_n, len(mix)):
            out[i - self.loop_n] += mix[i]
        y = 0.0
        for i in range(len(out)):
            y += (out[i] - y) * lowpass
            out[i] = y
        return out


def play_melody(tr, melody, start, beat, inst, vol, gate=0.92):
    t = start
    for bar in melody:
        for note, beats in bar:
            if note:
                tr.note(t, note, beats * beat * gate, inst, vol)
            t += beats * beat
    return t


# ================================================================ the songs
def lullaby():
    beat = 60 / 84
    bar = 3 * beat
    chords = ["D", "A", "B", "F#", "G", "D", "E", "A", "D", "A", "B", "G", "E", "A", "D", "D"]
    minor = {"B", "F#", "E"}
    melody = [
        [("F#5", 2), ("E5", 0.5), ("D5", 0.5)], [("E5", 2), ("C#5", 1)], [("D5", 1.5), ("B4", 0.5), ("D5", 1)],
        [("C#5", 3)], [("B4", 1), ("D5", 1), ("G5", 1)], [("F#5", 2), ("A4", 1)], [("G5", 1), ("F#5", 1), ("E5", 1)],
        [("E5", 3)], [("A5", 2), ("F#5", 1)], [("E5", 1.5), ("C#5", 0.5), ("A4", 1)], [("B4", 1), ("D5", 1), ("F#5", 1)],
        [("G5", 2), ("F#5", 0.5), ("E5", 0.5)], [("E5", 1), ("G5", 1), ("B5", 1)], [("A5", 2), ("G5", 0.5), ("E5", 0.5)],
        [("F#5", 2), ("E5", 1)], [("D5", 3)],
    ]
    passes = 2
    tr = Track(passes * len(chords) * bar)
    for p in range(passes):
        base = p * len(chords) * bar
        for i, root in enumerate(chords):
            t0 = base + i * bar
            third = 3 if root in minor else 4
            r = NOTES[root]
            names = [k for k, v in NOTES.items()]
            tone = lambda semis, octv: f"{names[(r + semis) % 12]}{octv + (r + semis) // 12}"
            tr.note(t0, f"{root}2" if r < 7 else f"{root}2", beat * 0.9, "soft", 0.32)
            for b in (1, 2):
                for semis in (0, third, 7):
                    tr.note(t0 + b * beat, tone(semis, 4), beat * 0.5, "soft", 0.07)
        play_melody(tr, melody, base, beat, "bell", 0.28)
        if p == 1:
            play_melody(tr, [[(up(n) if n else None, d) for n, d in b] for b in melody], base, beat, "bell", 0.06)
    return tr.render(wet=0.35)


def save(path, samples, peak=0.85):
    m = max(1e-9, max(abs(s) for s in samples))
    scale = peak / m
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print(path.relative_to(ROOT), f"{len(samples) / SR:.1f}s")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    save(OUT / "theme_lullaby.wav", lullaby())


if __name__ == "__main__":
    main()
