"""Render the original card-table sound effects from oscillators and filtered noise.

Run with Python 3, numpy, scipy and ffmpeg. No recordings or external samples
are used. Peak levels reserve room for several cues, voices and music together.
"""
import argparse
from pathlib import Path
import subprocess

import numpy as np
from scipy.signal import butter, sosfilt

RATE = 44100
ROOT = Path(__file__).resolve().parents[3]
RNG = np.random.default_rng(90417)


def timeline(seconds):
    return np.arange(round(seconds * RATE)) / RATE


def noise(seconds, low, high):
    samples = RNG.standard_normal(round(seconds * RATE))
    filt = butter(2, (low, high), fs=RATE, btype="bandpass", output="sos")
    return sosfilt(filt, samples)


def fade_edges(sound, attack=0.003, release=0.018):
    start = round(RATE * attack)
    stop = min(round(RATE * release), len(sound) - start)
    shape = (1,) * (sound.ndim - 1)
    sound[:start] *= np.sin(np.linspace(0, np.pi / 2, start)).reshape((start, *shape)) ** 2
    sound[-stop:] *= np.cos(np.linspace(0, np.pi / 2, stop)).reshape((stop, *shape)) ** 2
    return sound


def noise_tap(seconds, low, high, decay, attack=0.003):
    t = timeline(seconds)
    return fade_edges(noise(seconds, low, high) * np.exp(-t / decay), attack)


def gust(seconds, low, high, peak):
    t = timeline(seconds)
    center = t / seconds
    envelope = np.where(center < peak, center / peak, (1 - center) / (1 - peak))
    smoothed = np.sin(np.pi * envelope / 2) ** 2
    return noise(seconds, low, high) * smoothed


def pitched_drop(seconds, start, end, sweep_time, decay):
    t = timeline(seconds)
    # Integral of the frequency curve avoids the unnatural sweep of f(t)*t.
    phase = end * t + (start - end) * sweep_time * (1 - np.exp(-t / sweep_time))
    return fade_edges(np.sin(2 * np.pi * phase) * np.exp(-t / decay))


def resonance(seconds, base, color):
    t = timeline(seconds)
    signal = np.zeros_like(t)
    for ratio, strength, decay in color:
        freq = base * ratio
        signal += strength * np.sin(2 * np.pi * freq * t) * np.exp(-t / decay)
    return fade_edges(signal, 0.002, 0.035)


def layers(*sounds):
    """Mix (start time, waveform, amplitude, stereo pan) components."""
    result = np.zeros((max(round(offset * RATE) + len(sound) for offset, sound, _, _ in sounds), 2))
    for offset, sound, volume, pan in sounds:
        start = round(offset * RATE)
        # Small pans leave the main sound equally intelligible in a mono mix.
        result[start:start + len(sound)] += sound[:, None] * volume * np.sqrt([1 - pan, 1 + pan])
    return result


WOOD = [(1.0, 1.0, 0.044), (2.17, 0.19, 0.022), (3.05, 0.09, 0.011)]
STEEL = [(1.0, 0.90, 0.092), (1.73, 0.52, 0.052), (2.48, 0.31, 0.041), (3.66, 0.09, 0.020)]
GLASS = [(1.0, 0.80, 0.10), (2.09, 0.34, 0.063), (3.12, 0.12, 0.035)]
FELT = [(1.0, 1.0, 0.16), (2.0, 0.27, 0.095), (3.01, 0.08, 0.046), (4.02, 0.03, 0.031)]


def wood(base, seconds=0.11):
    return resonance(seconds, base, WOOD)


def steel(base, seconds=0.21):
    return resonance(seconds, base, STEEL)


def glass(base, seconds=0.25):
    return resonance(seconds, base, GLASS)


def felt(base, seconds=0.29):
    return resonance(seconds, base, FELT)


def phrase(notes, step, length=0.29):
    return layers(*[
        (i * step, felt(f, length), gain, 0.16 * (-1) ** i)
        for i, (f, gain) in enumerate(notes)
    ])


def body_hit(heavy=False):
    return layers(
        (0.0, pitched_drop(0.18 if heavy else 0.13, 215 if heavy else 252, 111 if heavy else 143, 0.018, 0.047), 0.87, 0.0),
        (0.0, noise_tap(0.067, 160, 1650, 0.016), 0.78 if heavy else 0.61, 0.0),
        (0.001, noise_tap(0.035, 850, 3150, 0.007), 0.34, -0.11),
        (0.014, wood(262 if heavy else 350, 0.095), 0.33, 0.09),
    )


def plated_contact():
    return layers(
        (0.0, steel(705, 0.23), 0.90, 0.0),
        (0.001, noise_tap(0.067, 900, 3650, 0.009), 0.47, -0.09),
        (0.013, wood(338, 0.09), 0.22, 0.11),
    )


def brittle_fragments():
    return layers(
        (0.032, glass(1138, 0.165), 0.37, 0.24),
        (0.054, noise_tap(0.095, 1710, 4980, 0.022), 0.49, -0.21),
        (0.085, glass(1520, 0.13), 0.32, -0.31),
        (0.119, glass(1875, 0.10), 0.21, 0.28),
        (0.147, wood(725, 0.10), 0.12, -0.19),
    )


def combine(stereo_a, stereo_b, second_gain):
    size = max(len(stereo_a), len(stereo_b))
    mixed = np.zeros((size, 2))
    mixed[:len(stereo_a)] += stereo_a
    mixed[:len(stereo_b)] += stereo_b * second_gain
    return mixed


def cues():
    files = {}
    files["click"] = (layers((0, wood(760, 0.075), 0.81, 0), (0.003, noise_tap(0.053, 650, 2350, 0.009), 0.27, 0)), 0.19)
    files["select"] = (layers((0, gust(0.061, 480, 2630, 0.42), 0.60, 0.12), (0.025, wood(618, 0.084), 0.60, 0)), 0.21)
    files["card_slide"] = (layers(
        (0.0, gust(0.16, 400, 2400, 0.3), 0.72, -0.17),
        (0.035, gust(0.16, 650, 3100, 0.49), 0.45, 0.16),
    ), 0.25)
    files["card"] = (layers(
        (0.0, noise_tap(0.07, 465, 2530, 0.012), 0.54, 0.0),
        (0.0, wood(465, 0.088), 0.84, 0.0),
    ), 0.30)
    files["draw"] = (layers(
        (0.0, gust(0.096, 390, 2350, 0.54), 0.67, -0.16),
        (0.048, gust(0.12, 455, 2780, 0.44), 0.52, 0.13),
        (0.09, wood(706, 0.11), 0.21, 0.03),
    ), 0.25)
    files["play"] = (layers((0.0, wood(523), 0.65, -0.13), (0.042, felt(783.99), 0.91, 0.13)), 0.38)
    files["slash"] = (layers(
        (0.0, gust(0.175, 360, 3180, 0.64), 0.87, -0.14),
        (0.046, gust(0.108, 1450, 5000, 0.59), 0.39, 0.14),
        (0.054, pitched_drop(0.091, 1950, 678, 0.022, 0.020), 0.14, 0.11),
    ), 0.44)
    files["hit"] = (body_hit(), 0.64)
    files["hit_heavy"] = (body_hit(heavy=True), 0.71)
    files["shield"] = (layers((0.0, glass(630), 0.68, 0.0), (0.056, glass(946), 0.65, 0.16)), 0.40)
    files["shield_block"] = (plated_contact(), 0.62)
    files["shield_crack"] = (combine(plated_contact(), brittle_fragments(), 0.9), 0.54)
    files["shield_break"] = (combine(plated_contact(), brittle_fragments(), 1.6), 0.67)
    files["dodge"] = (layers(
        (0.0, gust(0.09, 500, 2560, 0.57), 0.63, -0.20),
        (0.053, gust(0.105, 1000, 4200, 0.35), 0.53, 0.24),
        (0.078, glass(965, 0.17), 0.24, 0.20),
    ), 0.46)
    files["fire_hit"] = (layers(
        (0.0, pitched_drop(0.19, 218, 120, 0.031, 0.068), 0.65, 0.0),
        (0.0, gust(0.20, 190, 1720, 0.24), 0.95, 0.0),
        (0.038, noise_tap(0.135, 1150, 3810, 0.031), 0.27, -0.21),
        (0.084, noise_tap(0.079, 980, 3340, 0.018), 0.37, 0.19),
        (0.117, noise_tap(0.093, 1050, 4080, 0.021), 0.25, -0.17),
    ), 0.68)
    files["ice_hit"] = (layers(
        (0.0, wood(294), 0.56, 0.0),
        (0.002, noise_tap(0.060, 1000, 4510, 0.014), 0.90, 0.0),
        (0.020, glass(996, 0.23), 0.63, -0.14),
        (0.063, glass(1537, 0.20), 0.42, 0.23),
        (0.105, glass(1836, 0.14), 0.22, -0.23),
    ), 0.65)
    files["thunder_hit"] = (layers(
        (0.0, noise_tap(0.074, 870, 5010, 0.018, 0.001), 0.79, 0.0),
        (0.007, pitched_drop(0.18, 860, 161, 0.025, 0.039), 0.49, 0.14),
        (0.024, pitched_drop(0.24, 290, 120, 0.022, 0.066), 0.76, -0.12),
        (0.054, noise_tap(0.23, 120, 610, 0.088), 0.49, 0.12),
    ), 0.68)
    files["heal"] = (phrase([(391.99, 0.71), (523.25, 0.80), (659.25, 0.76)], 0.064, 0.37), 0.48)
    files["revive"] = (phrase([(392, 0.61), (523.25, 0.87), (659.25, 0.67), (783.99, 0.62)], 0.076, 0.39), 0.53)
    files["equip"] = (layers(
        (0.0, noise_tap(0.074, 925, 3900, 0.012), 0.50, -0.12),
        (0.012, steel(738, 0.145), 0.63, 0.0),
        (0.062, wood(358), 0.42, 0.17),
    ), 0.46)
    files["trick"] = (layers(
        (0.0, gust(0.12, 420, 2310, 0.36), 0.60, -0.2),
        (0.052, felt(522, 0.18), 0.64, 0.17),
        (0.102, felt(702, 0.17), 0.51, 0.0),
    ), 0.40)
    files["nullify"] = (layers(
        (0.0, glass(1084, 0.175), 0.73, 0.20),
        (0.049, pitched_drop(0.20, 1892, 570, 0.031, 0.040), 0.53, -0.2),
        (0.041, gust(0.14, 640, 2500, 0.4), 0.28, 0.0),
    ), 0.49)
    files["judge"] = (phrase([(463, 0.7), (587.33, 0.73), (783.99, 0.58)], 0.082, 0.26), 0.39)
    files["chain"] = (layers(
        (0.0, steel(415, 0.12), 0.59, -0.11),
        (0.038, steel(661, 0.12), 0.55, 0.18),
        (0.088, steel(533, 0.115), 0.42, 0.0),
    ), 0.42)
    files["skill"] = (layers(
        (0.0, gust(0.18, 470, 2410, 0.63), 0.45, 0.0),
        (0.035, felt(493.88, 0.29), 0.72, -0.2),
        (0.093, glass(740, 0.30), 0.61, 0.15),
        (0.15, felt(987.77, 0.30), 0.47, 0.06),
    ), 0.48)
    files["turn"] = (phrase([(392, 0.63), (587.33, 0.85)], 0.095, 0.34), 0.40)
    files["dying"] = (layers(
        (0.0, pitched_drop(0.155, 170, 96, 0.023, 0.033), 0.78, 0.0),
        (0.16, pitched_drop(0.14, 158, 100, 0.019, 0.027), 0.62, 0.0),
        (0.046, felt(277.18, 0.30), 0.22, 0.08),
    ), 0.48)
    files["death"] = (phrase([(392, 0.67), (329.63, 0.67), (261.63, 0.83)], 0.146, 0.55), 0.46)
    files["spree"] = (phrase([(440, 0.70), (587.33, 0.81), (739.99, 0.85), (880, 0.67)], 0.069, 0.40), 0.53)
    files["win"] = (phrase([(391.99, 0.58), (523.25, 0.75), (659.25, 0.71), (783.99, 0.82), (1046.5, 0.43)], 0.136, 0.62), 0.54)
    files["lose"] = (phrase([(440, 0.71), (392, 0.62), (349.23, 0.61), (261.63, 0.81)], 0.155, 0.61), 0.43)
    return files


def export(name, sound, peak, output):
    # Retain relative levels across sound families; use a short master fade.
    sound = fade_edges(sound, attack=0.001, release=0.022)
    sound = sound / np.max(np.abs(sound)) * (peak * 0.60)
    pcm = (sound * 32767).astype("<i2")
    subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE),
         "-ac", "2", "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "5", str(output / f"{name}.ogg")],
        input=pcm.tobytes(), check=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "game/assets/sfx")
    opts = parser.parse_args()
    opts.output.mkdir(parents=True, exist_ok=True)
    library = cues()
    for name, (sound, peak) in library.items():
        export(name, sound, peak, opts.output)
    print(f"Rendered {len(library)} original sound effects in {opts.output}")


if __name__ == "__main__":
    main()
