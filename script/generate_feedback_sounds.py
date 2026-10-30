#!/usr/bin/env python3
"""Deterministic short sine cues; no playback or system-volume changes."""
from pathlib import Path
import math
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parent.parent


def cue(name, duration, notes):
    samples = []
    for index in range(round(duration * RATE)):
        time = index / RATE
        value = 0.0
        for start, length, frequency, gain in notes:
            local = time - start
            if 0 <= local < length:
                attack = min(1, local / 0.018)
                release = min(1, (length - local) / 0.045)
                envelope = math.sin(attack * math.pi / 2) ** 2 * math.sin(release * math.pi / 2) ** 2
                value += gain * envelope * math.sin(2 * math.pi * frequency * local)
        assert abs(value) < 0.95
        samples.append(round(value * 32767))
    folder = ROOT / "Resources/Sounds"
    folder.mkdir(parents=True, exist_ok=True)
    with wave.open(str(folder / f"{name}.wav"), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(struct.pack(f"<{len(samples)}h", *samples))


if __name__ == "__main__":
    cue("softRise", 0.18, [(0, 0.11, 440, 0.34), (0.065, 0.115, 554.37, 0.30)])
    cue("softTap", 0.10, [(0, 0.10, 260, 0.42)])
    cue("lowDouble", 0.28, [(0, 0.105, 392, 0.44), (0.15, 0.13, 330, 0.44)])
