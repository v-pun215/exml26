import math
import os
import random
import struct
import wave

SFX_DIR = "front/audio/sfx"
MUSIC_DIR = "front/audio/music"
SFX_RATE = 44100
MUSIC_RATE = 22050


def _write_mono(path, rate, samples):
    peak = max(1e-9, max(abs(v) for v in samples))
    scale = min(1.0, 0.95 / peak)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        frames = bytearray()
        for v in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767))
        f.writeframes(bytes(frames))


def _write_stereo(path, rate, left, right):
    peak = max(1e-9, max(abs(v) for v in left + right))
    scale = min(1.0, 0.95 / peak)
    with wave.open(path, "w") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(rate)
        frames = bytearray()
        for l, r in zip(left, right):
            frames += struct.pack("<h", int(max(-1.0, min(1.0, l * scale)) * 32767))
            frames += struct.pack("<h", int(max(-1.0, min(1.0, r * scale)) * 32767))
        f.writeframes(bytes(frames))


def _env_ad(t, dur, attack, release):
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0


def _tone(freq, dur, rate, attack=0.01, release=0.08, overtone=0.0):
    n = int(dur * rate)
    out = []
    for i in range(n):
        t = i / rate
        env = _env_ad(t, dur, attack, release)
        v = math.sin(2 * math.pi * freq * t)
        if overtone > 0.0:
            v += overtone * math.sin(2 * math.pi * freq * 2 * t)
        out.append(v * env)
    return out


def _mix_at(buf, start_sample, sound, gain=1.0):
    for i, v in enumerate(sound):
        idx = start_sample + i
        if idx < 0:
            continue
        while idx >= len(buf):
            buf.append(0.0)
        buf[idx] += v * gain


def make_jump():
    n = int(0.14 * SFX_RATE)
    out = []
    for i in range(n):
        t = i / SFX_RATE
        freq = 320.0 + (620.0 - 320.0) * (t / 0.14)
        env = _env_ad(t, 0.14, 0.005, 0.09)
        out.append(math.sin(2 * math.pi * freq * t) * env * 0.5)
    _write_mono(os.path.join(SFX_DIR, "jump.wav"), SFX_RATE, out)


def make_land():
    n = int(0.16 * SFX_RATE)
    rng = random.Random(7)
    out = []
    for i in range(n):
        t = i / SFX_RATE
        env = math.exp(-t / 0.045)
        body = math.sin(2 * math.pi * 90.0 * t) * env * 0.6
        click = (rng.random() * 2.0 - 1.0) * 0.25 * math.exp(-t / 0.006) if t < 0.01 else 0.0
        out.append(body + click)
    _write_mono(os.path.join(SFX_DIR, "land.wav"), SFX_RATE, out)


def make_grab():
    buf = []
    _mix_at(buf, 0, _tone(880.00, 0.14, SFX_RATE, 0.005, 0.1, overtone=0.25), 0.45)
    _mix_at(buf, int(0.08 * SFX_RATE), _tone(1174.66, 0.18, SFX_RATE, 0.005, 0.13, overtone=0.25), 0.45)
    _write_mono(os.path.join(SFX_DIR, "grab.wav"), SFX_RATE, buf)


def make_score():
    notes = [523.25, 659.25, 783.99, 1046.50]
    buf = []
    for i, freq in enumerate(notes):
        start = int(i * 0.11 * SFX_RATE)
        _mix_at(buf, start, _tone(freq, 0.22, SFX_RATE, 0.004, 0.17, overtone=0.3), 0.4)
    _write_mono(os.path.join(SFX_DIR, "score.wav"), SFX_RATE, buf)


def make_ambient_loop():
    chords = [
        [220.00, 261.63, 329.63, 392.00],
        [174.61, 220.00, 261.63, 329.63],
        [130.81, 164.81, 196.00, 246.94],
        [196.00, 246.94, 293.66, 329.63],
    ]
    seg_dur = 4.0
    attack, release = 0.5, 0.5
    left, right = [], []
    for chord in chords:
        n = int(seg_dur * MUSIC_RATE)
        for i in range(n):
            t = i / MUSIC_RATE
            env = _env_ad(t, seg_dur, attack, release)
            tremolo = 1.0 + 0.08 * math.sin(2 * math.pi * 0.15 * t)
            vl = 0.0
            vr = 0.0
            for freq in chord:
                vl += math.sin(2 * math.pi * (freq - 0.12) * t)
                vr += math.sin(2 * math.pi * (freq + 0.12) * t)
            amp = env * tremolo * 0.22 / len(chord)
            left.append(vl * amp)
            right.append(vr * amp)
    _write_stereo(os.path.join(MUSIC_DIR, "ambient_loop.wav"), MUSIC_RATE, left, right)


def main():
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)
    make_jump()
    make_land()
    make_grab()
    make_score()
    make_ambient_loop()
    print("wrote sfx + ambient loop")


if __name__ == "__main__":
    main()
