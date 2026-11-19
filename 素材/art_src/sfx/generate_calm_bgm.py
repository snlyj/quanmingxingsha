#!/usr/bin/env python3
"""Render the two original ambient scores from notes and synthesized instruments.

Requires NumPy and FFmpeg with libvorbis. No samples or other media are read.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess

import numpy as np


RATE = 44100

# Chords carry a root followed by quiet open voicings. Each beat varies between
# a bass note, a single midrange note or silence, leaving room for game audio.
CHORDS = {
    "Dmaj9": (50, 57, 61, 64, 66),
    "Bm7": (47, 54, 57, 62, 66),
    "Gmaj7": (43, 55, 59, 62, 66),
    "Em9": (40, 55, 59, 62, 66),
    "Aadd9": (45, 57, 59, 61, 64),
    "Asus4": (45, 57, 62, 64, 69),
    "Dadd9": (50, 57, 62, 64, 66),
    "Am9": (45, 57, 60, 64, 71),
    "Fmaj7": (41, 53, 57, 60, 64),
    "Cmaj9": (48, 55, 59, 62, 64),
    "Gsus4": (43, 55, 60, 62, 67),
    "Gadd9": (43, 55, 57, 59, 62),
    "Dm9": (50, 57, 60, 64, 65),
    "Bbmaj7": (46, 53, 57, 62, 65),
    "Gm9": (43, 57, 58, 62, 65),
    "F6": (41, 53, 57, 62, 65),
    "Ebmaj7": (39, 55, 58, 62, 67),
}

# Phrases are (beat offset, MIDI note, velocity). Half bars can breathe.
SCORES = {
    "home": (64, [
        ("Dmaj9", [(0.45, 69, .41), (1.70, 73, .34), (2.85, 76, .38)]),
        ("Bm7", [(0.18, 78, .27), (1.35, 76, .35), (2.75, 73, .31)]),
        ("Gmaj7", [(0.60, 74, .37), (2.32, 71, .27), (3.33, 69, .27)]),
        ("Aadd9", [(0.40, 71, .32), (2.10, 69, .30)]),
        ("Bm7", [(0.44, 66, .34), (1.84, 69, .38), (2.90, 73, .40)]),
        ("Gmaj7", [(0.15, 74, .36), (1.88, 73, .27), (3.08, 69, .26)]),
        ("Em9", [(0.40, 71, .36), (2.54, 67, .32)]),
        ("Asus4", [(0.50, 64, .34), (1.62, 66, .30), (3.00, 69, .31)]),
        ("Dmaj9", [(0.45, 73, .36), (1.72, 76, .31), (3.15, 78, .30)]),
        ("Gmaj7", [(0.52, 79, .28), (2.22, 76, .33), (3.24, 74, .25)]),
        ("Em9", [(0.65, 71, .35), (2.17, 73, .34), (3.44, 74, .27)]),
        ("Aadd9", [(0.58, 76, .32), (2.67, 69, .30)]),
    ]),
    "draft": (68, [
        ("Em9", [(0.25, 67, .34), (1.76, 71, .31), (3.12, 74, .26)]),
        ("Cmaj9", [(0.82, 76, .29), (2.66, 74, .28)]),
        ("Gadd9", [(0.40, 71, .32), (1.97, 69, .25)]),
        ("Dadd9", [(0.90, 66, .25), (2.68, 69, .28)]),
        ("Em9", [(0.35, 71, .30), (2.22, 74, .27), (3.10, 76, .25)]),
        ("Cmaj9", [(0.57, 79, .28), (2.45, 76, .25)]),
        ("Gadd9", [(0.61, 74, .31), (1.82, 71, .28), (3.14, 69, .26)]),
        ("Dadd9", [(0.73, 66, .24), (2.81, 69, .24)]),
    ]),
    "battle": (70, [
        ("Am9", [(0.62, 67, .32), (1.83, 69, .29), (3.14, 71, .27)]),
        ("Fmaj7", [(0.18, 72, .30), (1.64, 69, .26)]),
        ("Cmaj9", [(0.83, 67, .27), (2.45, 64, .27)]),
        ("Gsus4", [(0.65, 67, .28), (2.01, 69, .24), (3.02, 74, .25)]),
        ("Am9", [(0.35, 76, .33), (2.20, 72, .26)]),
        ("Fmaj7", [(0.72, 74, .28), (2.51, 69, .29)]),
        ("Dm9", [(0.69, 65, .29), (1.82, 67, .25), (3.13, 69, .25)]),
        ("Gsus4", [(0.63, 74, .29), (2.58, 72, .28)]),
        ("Cmaj9", [(0.44, 71, .28), (2.29, 67, .25)]),
        ("Fmaj7", [(0.72, 69, .28), (1.92, 64, .27)]),
        ("Dm9", [(0.75, 65, .25), (2.35, 67, .23)]),
        ("Gsus4", [(1.15, 69, .25), (2.76, 74, .23)]),
    ]),
    "tense": (72, [
        ("Dm9", [(0.38, 65, .29), (1.90, 69, .28), (3.12, 72, .27)]),
        ("Bbmaj7", [(0.52, 74, .28), (2.48, 69, .25)]),
        ("Gm9", [(0.79, 70, .31), (1.89, 69, .26), (3.04, 65, .24)]),
        ("Asus4", [(0.63, 64, .29), (2.18, 67, .26)]),
        ("Dm9", [(0.40, 69, .30), (1.89, 72, .28), (3.08, 76, .27)]),
        ("F6", [(0.60, 77, .30), (2.47, 72, .25)]),
        ("Ebmaj7", [(0.49, 74, .27), (1.89, 70, .29), (3.08, 67, .26)]),
        ("Asus4", [(0.65, 69, .30), (2.46, 64, .26)]),
    ]),
}

RESULTS = {
    "win": [(0.10, 62, .28), (0.24, 66, .31), (0.47, 69, .34),
            (0.70, 74, .36), (0.88, 78, .30), (1.16, 81, .23)],
    "lose": [(0.10, 50, .26), (0.36, 69, .31), (0.62, 66, .29),
             (0.89, 64, .27), (1.16, 62, .23)],
}


def instrument(kind: str, pitch: int, duration: float) -> np.ndarray:
    t = np.arange(int(duration * RATE), dtype=np.float64) / RATE
    freq = 440.0 * 2.0 ** ((pitch - 69) / 12.0)
    data = np.zeros(t.size)
    if kind == "pad":
        phase = 2.0 * np.pi * freq * t
        vibrato = np.sin(t * 2.0 * np.pi * 0.36) * 0.23
        data = (0.81 * np.sin(phase + vibrato)
                + 0.23 * np.sin(phase * 0.9981 - vibrato)
                + 0.19 * np.sin(phase * 2.0007) + 0.055 * np.sin(phase * 3.001))
        envelope = np.sin(np.pi / 2.0 * np.minimum(t / 1.16, 1.0)) ** 2
        envelope *= np.sin(np.pi / 2.0 * np.minimum((duration - t) / 1.25, 1.0)) ** 2
        return data * envelope

    if kind == "felt":
        partials, attack, decay, stiffness = (1.0, .30, .15, .068, .026, .009), .018, .89, .00017
    elif kind == "koto":
        partials, attack, decay, stiffness = (1.0, .48, .24, .12, .047, .020), .011, .48, .00029
    else:
        partials, attack, decay, stiffness = (1.0, .20, .15, .046, .028), .026, 1.12, .00064

    decay *= 2 ** ((67 - pitch) / 112.0)
    for idx, amount in enumerate(partials):
        harmonic = idx + 1.0
        phase = 2 * np.pi * freq * harmonic * (1 + stiffness * idx * idx) * t
        ring = np.sin(phase + 0.21 * idx)
        if kind == "felt" or kind == "keys":
            ring = 0.68 * ring + 0.32 * np.sin(phase * 1.00092 - 0.24 * idx)
        # High partials disappear early under a felt hammer or soft pluck.
        data += amount * ring * np.exp(-t * (1 + idx * .71) / decay)
    envelope = np.sin(np.pi / 2.0 * np.minimum(t / attack, 1.0)) ** 2
    envelope *= np.sin(np.pi / 2.0 * np.minimum((duration - t) / .29, 1.0)) ** 2
    return data * envelope


def add_note(audio: np.ndarray, onset: float, pitch: int, level: float,
             kind: str, pan: float, duration: float, loop: bool) -> None:
    note = instrument(kind, pitch, duration)
    n = audio.shape[0]
    first = int(onset * RATE)
    if loop:
        first %= n
    gain = level * np.sqrt(np.array([(1.0 - pan) * 0.5, (1.0 + pan) * 0.5]))
    end = min(n, first + note.size)
    audio[first:end] += note[:end-first, None] * gain
    if loop and end-first < note.size:
        tail = note[end-first:]
        audio[:tail.size] += tail[:, None] * gain


def room(dry: np.ndarray, loop: bool) -> np.ndarray:
    wet = dry.copy()
    for channel, taps in enumerate((
        ((.031, .072), (.071, .055), (.119, .043), (.196, .034), (.348, .023), (.546, .014)),
        ((.043, .072), (.086, .052), (.139, .044), (.229, .032), (.402, .020), (.624, .014)),
    )):
        spread = 0.66 * dry[:, channel] + 0.34 * dry[:, 1-channel]
        # Low-pass the reflections by averaging several neighboring samples.
        spread = sum(np.roll(spread, i) for i in range(0, 13, 2)) / 7
        for delay, decay in taps:
            shift = int(delay * RATE)
            if loop:
                wet[:, channel] += np.roll(spread, shift) * decay
            else:
                wet[shift:, channel] += spread[:-shift] * decay
    return wet


def render(scene: str, moon: bool) -> np.ndarray:
    bpm, bars = SCORES[scene]
    beat = 60.0 / (bpm - (3 if moon else 0))
    n = round(4 * len(bars) * beat * RATE)
    mix = np.zeros((n, 2), dtype=np.float64)
    for idx, (name, melody) in enumerate(bars):
        root, low, inner, upper, high = CHORDS[name]
        t = idx * beat * 4
        # Open-voiced felt keys rather than a continuous rhythmic ostinato.
        tone = "keys" if moon else "felt"
        add_note(mix, t + .03, root, .116, tone, -.18, 2.8, True)
        add_note(mix, t + beat * (.84 if moon else 1.03), low, .080, tone, -.05, 2.5, True)
        if idx % 3 != 1:
            add_note(mix, t + beat * 2.38, inner, .039, tone, .17, 1.8, True)
        if idx % 2 == 1:
            add_note(mix, t + beat * 3.03, upper, .045, tone, .12, 2.0, True)
        for p_idx, pitch in enumerate((low, inner, upper, high)):
            pan = (-.30, -.09, .17, .33)[p_idx]
            level = (.019, .018, .016, .010)[p_idx] * (1.38 if moon else 1.0)
            add_note(mix, t - .34 + .038 * p_idx, pitch, level, "pad", pan, 4.0 * beat + .47, True)
        for note_idx, (offset, pitch, velocity) in enumerate(melody):
            if moon:
                lead = "felt" if note_idx == 1 else "keys"
                pitch -= 12 if pitch >= 76 else 0
                offset += .09
            else:
                lead = "koto" if (idx + note_idx) % 3 == 1 else "felt"
            add_note(mix, t + beat * offset, pitch, velocity,
                     lead, .22 if lead == "koto" else .04, 2.85 if lead != "koto" else 1.75, True)
    return room(mix, True)


def result(name: str) -> np.ndarray:
    mix = np.zeros((round(3.6 * RATE), 2), dtype=np.float64)
    add_note(mix, .05, 50 if name == "win" else 47, .085, "felt", -.19, 2.6, False)
    for onset, pitch, level in RESULTS[name]:
        add_note(mix, onset, pitch, level, "felt", .08, 2.35, False)
    mix = room(mix, False)
    mix *= np.minimum(np.arange(mix.shape[0])[::-1] / (RATE * .3), 1.0)[:, None]
    return mix


def write_ogg(audio: np.ndarray, path: Path) -> None:
    audio -= np.mean(audio, axis=0)
    peak_db = 20 * np.log10(np.max(np.abs(audio)))
    raw = audio.astype("<f4").tobytes()
    input_args = ["ffmpeg", "-nostdin", "-hide_banner", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-"]
    measurement = subprocess.run(
        [*input_args, "-af", "ebur128=framelog=verbose", "-f", "null", "-"],
        input=raw, capture_output=True, check=True).stderr.decode()
    integrated = float(measurement.rsplit("Integrated loudness:", 1)[-1].split("I:", 1)[-1].split()[0])
    gain_db = min(-22.7 - integrated, -7.5 - peak_db)
    subprocess.run(
        [*input_args, "-v", "error", "-y", "-af", f"volume={gain_db:.4f}dB",
         "-c:a", "libvorbis", "-q:a", "3", str(path)],
        input=raw, check=True)
    print(f"{path.name}: {audio.shape[0]/RATE:.2f}s, {path.stat().st_size / 1024:.1f} KiB, {integrated+gain_db:.1f} LUFS")


def main() -> None:
    default_dir = Path(__file__).resolve().parents[3] / "game" / "assets" / "bgm"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=default_dir)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for palette in ("sakura", "moon"):
        for scene in SCORES:
            write_ogg(render(scene, palette == "moon"), args.output / f"{palette}_{scene}.ogg")
    for name in RESULTS:
        write_ogg(result(name), args.output / f"result_{name}.ogg")


if __name__ == "__main__":
    main()
