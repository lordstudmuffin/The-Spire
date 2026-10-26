#!/usr/bin/env python3
"""Crystal interface sound set for The Spire.

Every sound here is synthesized from scratch (additive sines, FM, filtered
noise and a generated reverb tail), so the whole set is original and can be
regenerated or tweaked at any time:

    python3 tools/sfx/gen_crystal.py [out_dir]

Default output is assets/audio/crystal/*.ogg (needs ffmpeg with libvorbis).
Pitches share one key (A major) so menu, loot and level sounds feel like one
family. Tweak the recipes at the bottom; each one is a few lines.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
RNG = np.random.default_rng(7)

# A major, around the bright 5th/6th octave the menu lives in.
A4 = 440.0


def note(semis_from_a4):
	return A4 * 2.0 ** (semis_from_a4 / 12.0)


def t_axis(dur):
	return np.arange(int(dur * SR)) / SR


def env_exp(dur, attack=0.004, decay=0.25):
	t = t_axis(dur)
	a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
	return a * np.exp(-np.maximum(t - attack, 0.0) / decay)


def env_adsr(dur, a=0.01, d=0.1, s=0.6, r=0.3):
	t = t_axis(dur)
	out = np.ones_like(t) * s
	out[t < a] = t[t < a] / a
	m = (t >= a) & (t < a + d)
	out[m] = 1.0 - (1.0 - s) * (t[m] - a) / d
	rel = t > dur - r
	out[rel] *= np.clip((dur - t[rel]) / r, 0.0, 1.0)
	return out


def glass(freq, dur, decay=0.35, bright=1.0, glide=0.0, glide_time=0.04):
	"""Glass/crystal tone: inharmonic sine partials, upper ones die faster."""
	t = t_axis(dur)
	# Optional short pitch glide into the note (the soft "pyon" of a menu chime).
	f = freq * (1.0 + glide * np.exp(-t / max(glide_time, 1e-4)))
	phase = 2 * np.pi * np.cumsum(f) / SR
	partials = [(1.0, 1.0, 1.0), (2.0, 0.35 * bright, 0.55), (2.76, 0.22 * bright, 0.4),
		(5.40, 0.10 * bright, 0.22), (8.93, 0.05 * bright, 0.12)]
	out = np.zeros_like(t)
	for ratio, amp, dk in partials:
		out += amp * np.sin(phase * ratio) * np.exp(-t / (decay * dk))
	att = np.clip(t / 0.002, 0, 1)
	return out * att


def fm_bell(freq, dur, index=2.5, ratio=3.5, decay=0.5):
	t = t_axis(dur)
	mod_env = np.exp(-t / (decay * 0.4))
	mod = index * mod_env * np.sin(2 * np.pi * freq * ratio * t)
	return np.sin(2 * np.pi * freq * t + mod) * np.exp(-t / decay) * np.clip(t / 0.002, 0, 1)


def noise(dur):
	return RNG.standard_normal(int(dur * SR))


def one_pole_lp(x, cutoff):
	a = np.exp(-2 * np.pi * cutoff / SR)
	y = np.empty_like(x)
	acc = 0.0
	for i, v in enumerate(x):
		acc = (1 - a) * v + a * acc
		y[i] = acc
	return y


def hp(x, cutoff):
	return x - one_pole_lp(x, cutoff)


def band_noise(dur, lo, hi):
	"""Band-limited noise via FFT masking (fast, no filter state needed)."""
	n = int(dur * SR)
	spec = np.fft.rfft(RNG.standard_normal(n))
	fr = np.fft.rfftfreq(n, 1 / SR)
	spec[(fr < lo) | (fr > hi)] = 0
	out = np.fft.irfft(spec, n)
	return out / (np.max(np.abs(out)) + 1e-9)


def sweep_noise(dur, f0, f1, width=0.5):
	"""Noise whose band slides from f0 to f1 (whooshes, panel slides)."""
	n = int(dur * SR)
	hop = 512
	out = np.zeros(n + hop * 2)
	win = np.hanning(hop * 2)
	for k, start in enumerate(range(0, n, hop)):
		fc = f0 + (f1 - f0) * (start / max(n - 1, 1))
		seg = band_noise(hop * 2 / SR, fc * (1 - width), fc * (1 + width))
		out[start:start + hop * 2] += seg * win
	return out[:n]


def place(buf, sig, at, gain=1.0):
	i = int(at * SR)
	end = min(len(buf), i + len(sig))
	buf[i:end] += sig[:end - i] * gain
	return buf


def reverb(x, wet=0.25, size=1.2, damp=6000.0, predelay=0.012):
	"""Convolve with a generated decaying-noise impulse (stereo-free, mono)."""
	n_ir = int(size * SR)
	t = np.arange(n_ir) / SR
	ir = RNG.standard_normal(n_ir) * np.exp(-t / (size / 5.0))
	ir = one_pole_lp(ir, damp)
	ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
	ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
	n = len(x) + len(ir)
	nfft = 1 << (n - 1).bit_length()
	y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:n]
	dry = np.concatenate([x, np.zeros(len(ir))])
	return dry * (1 - wet * 0.5) + y * wet


def finish(x, peak=0.89, fade=0.02, trim_db=-60.0):
	x = x - np.mean(x)
	m = np.max(np.abs(x)) + 1e-9
	x = x / m * peak
	# Trim the silent tail.
	thr = peak * 10 ** (trim_db / 20)
	idx = np.where(np.abs(x) > thr)[0]
	if len(idx):
		x = x[: min(len(x), idx[-1] + int(0.02 * SR))]
	f = min(int(fade * SR), len(x))
	x[-f:] *= np.linspace(1, 0, f)
	return x


# ---------------------------------------------------------------- recipes ---

def menu_open():
	b = np.zeros(int(1.4 * SR))
	place(b, glass(note(24), 1.0, decay=0.45, glide=-0.06), 0.0, 0.7)       # A6
	place(b, glass(note(31), 1.0, decay=0.5, glide=-0.05), 0.075, 0.6)      # E7
	place(b, band_noise(0.35, 6000, 14000) * env_exp(0.35, 0.03, 0.08), 0.02, 0.06)
	for i, s in enumerate([36, 40, 43]):                                    # shimmer
		place(b, glass(note(s), 0.5, decay=0.15, bright=0.4), 0.14 + i * 0.035, 0.12)
	return reverb(b, 0.35, 1.0)


def menu_close():
	b = np.zeros(int(1.2 * SR))
	place(b, glass(note(31), 0.8, decay=0.35, glide=0.03), 0.0, 0.55)
	place(b, glass(note(24), 0.9, decay=0.4, glide=0.03), 0.07, 0.6)
	place(b, sweep_noise(0.25, 9000, 3000) * env_exp(0.25, 0.01, 0.07), 0.0, 0.05)
	return reverb(b, 0.3, 0.9)


def menu_select():
	b = glass(note(36), 0.18, decay=0.05, bright=0.6)                        # A7 tick
	return reverb(b, 0.15, 0.4)


def menu_confirm():
	b = np.zeros(int(0.8 * SR))
	place(b, glass(note(28), 0.6, decay=0.22, glide=-0.04), 0.0, 0.7)       # C#7
	place(b, glass(note(33), 0.6, decay=0.25), 0.05, 0.55)                  # F#7
	return reverb(b, 0.28, 0.8)


def menu_back():
	b = np.zeros(int(0.6 * SR))
	place(b, glass(note(28), 0.5, decay=0.15), 0.0, 0.6)
	place(b, glass(note(24), 0.5, decay=0.18), 0.045, 0.6)
	return reverb(b, 0.22, 0.6)


def menu_error():
	b = np.zeros(int(0.6 * SR))
	for i in range(2):
		place(b, fm_bell(note(10), 0.25, index=4.0, ratio=1.41, decay=0.07), i * 0.1, 0.5)
	return reverb(b, 0.15, 0.4)


def panel_slide():
	b = sweep_noise(0.32, 2500, 7500, 0.35) * env_adsr(0.32, 0.06, 0.08, 0.6, 0.18)
	b = b * 0.35
	place(b, glass(note(36), 0.2, decay=0.06, bright=0.3), 0.02, 0.15)
	return reverb(b, 0.2, 0.5)


def notify():
	b = np.zeros(int(1.1 * SR))
	place(b, fm_bell(note(28), 0.8, index=1.4, ratio=2.0, decay=0.28), 0.0, 0.6)
	place(b, fm_bell(note(35), 0.8, index=1.2, ratio=2.0, decay=0.32), 0.11, 0.55)
	return reverb(b, 0.35, 1.0)


def party_invite():
	b = np.zeros(int(1.3 * SR))
	for i, s in enumerate([24, 28, 31, 36]):
		place(b, fm_bell(note(s), 0.7, index=1.2, ratio=2.0, decay=0.3), i * 0.07, 0.45)
	return reverb(b, 0.35, 1.1)


def _arp(steps, gap, decay, gain=0.5, glass_tone=True):
	dur = gap * len(steps) + decay * 6
	b = np.zeros(int(dur * SR))
	for i, s in enumerate(steps):
		sig = glass(note(s), decay * 5, decay=decay) if glass_tone else fm_bell(note(s), decay * 5, decay=decay)
		place(b, sig, i * gap, gain)
	return b


def item_get():
	b = _arp([24, 28, 31, 36], 0.055, 0.12, 0.5)
	place(b, band_noise(0.3, 7000, 15000) * env_exp(0.3, 0.02, 0.08), 0.12, 0.05)
	return reverb(b, 0.3, 0.8)


def item_rare():
	b = _arp([19, 24, 28, 31, 36, 40, 43], 0.06, 0.18, 0.45)
	b = np.concatenate([b, np.zeros(int(0.8 * SR))])
	pad = np.zeros(int(1.6 * SR))
	for s in (24, 28, 31):
		pad += np.sin(2 * np.pi * note(s) * t_axis(1.6)) * 0.12
	place(b, pad * env_adsr(1.6, 0.2, 0.3, 0.6, 0.9), 0.25, 1.0)
	for k in range(14):
		place(b, glass(note(40 + RNG.integers(0, 10)), 0.3, decay=0.06, bright=0.3), 0.3 + k * 0.05, 0.12)
	return reverb(b, 0.4, 1.4)


def level_up():
	b = np.zeros(int(2.8 * SR))
	place(b, _arp([12, 16, 19, 24, 28, 31, 36], 0.07, 0.2, 0.5), 0.0, 1.0)
	# Choir-ish pad: detuned saws softened by a low-pass, swelling under the arp.
	t = t_axis(2.0)
	pad = np.zeros_like(t)
	for s in (12, 16, 19, 24):
		for det in (-0.08, 0.0, 0.08):
			f = note(s + det)
			pad += (2 * ((f * t) % 1.0) - 1) * 0.04
	pad = one_pole_lp(pad, 2200)
	place(b, pad * env_adsr(2.0, 0.35, 0.3, 0.7, 1.0), 0.3, 1.0)
	place(b, glass(note(36), 1.6, decay=0.6), 0.5, 0.45)
	place(b, glass(note(43), 1.6, decay=0.6), 0.5, 0.25)
	for k in range(22):
		place(b, glass(note(38 + RNG.integers(0, 14)), 0.25, decay=0.05, bright=0.3), 0.45 + k * 0.04, 0.1)
	return reverb(b, 0.4, 1.6)


def quest_accept():
	b = np.zeros(int(0.9 * SR))
	place(b, glass(note(19), 0.6, decay=0.22), 0.0, 0.55)
	place(b, glass(note(26), 0.6, decay=0.24), 0.06, 0.5)
	place(b, glass(note(31), 0.7, decay=0.3), 0.12, 0.45)
	return reverb(b, 0.3, 0.9)


def quest_complete():
	b = np.zeros(int(2.2 * SR))
	place(b, _arp([19, 23, 26, 31], 0.09, 0.2, 0.5), 0.0, 1.0)
	chord = sum(glass(note(s), 1.6, decay=0.6) for s in (24, 28, 31, 36))
	place(b, chord, 0.38, 0.35)
	return reverb(b, 0.38, 1.4)


def hit_digital():
	"""High 'digital' tick layered on top of the impact sounds."""
	b = fm_bell(note(39), 0.12, index=3.0, ratio=1.5, decay=0.025)
	place(b, band_noise(0.05, 4000, 12000) * env_exp(0.05, 0.001, 0.012), 0.0, 0.4)
	return reverb(b, 0.08, 0.25)


def crit_digital():
	b = np.zeros(int(0.4 * SR))
	place(b, fm_bell(note(43), 0.25, index=4.0, ratio=1.5, decay=0.05), 0.0, 0.6)
	place(b, fm_bell(note(36), 0.3, index=2.0, ratio=2.0, decay=0.08), 0.015, 0.5)
	place(b, band_noise(0.08, 3000, 14000) * env_exp(0.08, 0.001, 0.02), 0.0, 0.5)
	return reverb(b, 0.12, 0.35)


def _shatter(dur, shards, low_crunch, tail):
	b = np.zeros(int((dur + tail) * SR))
	# Glass-burst crunch: a sharp broadband crack plus a lower body thump.
	place(b, band_noise(0.12, 1500, 16000) * env_exp(0.12, 0.0008, 0.03), 0.0, 0.9)
	place(b, band_noise(0.2, 120, 900) * env_exp(0.2, 0.001, 0.05), 0.0, low_crunch)
	# Many tiny glass pings with randomized pitch, density falling over time
	# and pitch drifting downward: the "falling sparkle" tail.
	for k in range(shards):
		at = (k / shards) ** 1.7 * dur
		semis = 30 + RNG.uniform(0, 20) - at / dur * 10
		place(b, glass(note(semis), 0.35, decay=RNG.uniform(0.03, 0.09), bright=0.5), at + RNG.uniform(0, 0.02),
			RNG.uniform(0.08, 0.22) * (1 - 0.6 * at / dur))
	# Airy sparkle wash.
	place(b, sweep_noise(dur, 11000, 6000, 0.3) * env_exp(dur, 0.02, dur * 0.35), 0.03, 0.12)
	return reverb(b, 0.35, 1.0 + tail)


def shatter():
	return _shatter(0.6, 40, 0.5, 0.4)


def shatter_boss():
	b = _shatter(1.4, 110, 0.9, 1.0)
	low = np.zeros(int(1.5 * SR))
	t = t_axis(1.5)
	low += np.sin(2 * np.pi * (55 * np.exp(-t * 1.2) + 30) * t) * np.exp(-t / 0.5) * 0.8
	place(b, low, 0.0, 0.8)
	return b


def player_death():
	b = np.zeros(int(3.0 * SR))
	place(b, _shatter(0.8, 50, 0.6, 0.6), 0.0, 1.0)
	# Slow descending minor glass line under it.
	for i, s in enumerate([24, 20, 17, 12]):
		place(b, glass(note(s), 1.4, decay=0.55, bright=0.6), 0.35 + i * 0.28, 0.3)
	return reverb(b, 0.45, 1.8)


def respawn():
	b = np.zeros(int(1.8 * SR))
	place(b, sweep_noise(0.9, 1500, 9000, 0.3) * env_adsr(0.9, 0.4, 0.2, 0.7, 0.3), 0.0, 0.18)
	place(b, _arp([12, 19, 24, 28, 31], 0.08, 0.2, 0.4), 0.45, 1.0)
	return reverb(b, 0.4, 1.3)


def heartbeat():
	b = np.zeros(int(0.75 * SR))
	t = t_axis(0.18)
	thump = np.sin(2 * np.pi * (70 * np.exp(-t * 8) + 38) * t) * np.exp(-t / 0.05)
	place(b, thump, 0.0, 0.9)
	place(b, thump, 0.2, 0.6)
	return finish(b, trim_db=-70.0)


def realm_announce():
	"""Server-wide fanfare for unique skills / last limited slot taken."""
	b = np.zeros(int(3.2 * SR))
	place(b, _arp([7, 12, 16, 19, 24], 0.11, 0.3, 0.45), 0.0, 1.0)
	chord = sum(glass(note(s), 2.4, decay=0.9) for s in (12, 19, 24, 28, 31))
	place(b, chord, 0.6, 0.3)
	t = t_axis(2.6)
	pad = sum(np.sin(2 * np.pi * note(s) * t) for s in (0, 7, 12)) * 0.1
	place(b, pad * env_adsr(2.6, 0.5, 0.4, 0.7, 1.2), 0.4, 1.0)
	return reverb(b, 0.45, 2.0)


def skill_charge():
	"""Sword Art wind-up: rising shimmer."""
	b = sweep_noise(0.4, 2000, 10000, 0.25) * env_adsr(0.4, 0.3, 0.05, 0.8, 0.08) * 0.4
	t = t_axis(0.4)
	b += np.sin(2 * np.pi * np.cumsum(note(19) * (1 + t * 1.5)) / SR) * env_adsr(0.4, 0.2, 0.05, 0.6, 0.1) * 0.3
	return reverb(b, 0.25, 0.6)


def metal(freq, dur, decay=0.25):
	"""Struck-blade clang: dense inharmonic partials, bright attack."""
	t = t_axis(dur)
	out = np.zeros_like(t)
	for ratio, amp, dk in [(1.0, 1.0, 1.0), (2.41, 0.7, 0.7), (3.93, 0.5, 0.5), (5.62, 0.35, 0.35), (7.31, 0.25, 0.25), (9.8, 0.15, 0.15)]:
		out += amp * np.sin(2 * np.pi * freq * ratio * t + RNG.uniform(0, 6.28)) * np.exp(-t / (decay * dk))
	return out * np.clip(t / 0.0008, 0, 1)


def parry():
	"""Perfect parry: sharp blade clang, a bright glass ring and a shimmer."""
	b = np.zeros(int(1.4 * SR))
	place(b, band_noise(0.05, 2500, 16000) * env_exp(0.05, 0.0005, 0.01), 0.0, 0.9)
	place(b, metal(note(19), 0.9, 0.22), 0.0, 0.6)
	place(b, metal(note(26) * 1.01, 0.9, 0.18), 0.002, 0.4)
	place(b, glass(note(36), 1.0, decay=0.35), 0.01, 0.5)
	place(b, glass(note(43), 1.0, decay=0.3, bright=0.5), 0.03, 0.25)
	place(b, sweep_noise(0.5, 12000, 7000, 0.25) * env_exp(0.5, 0.01, 0.15), 0.02, 0.1)
	return reverb(b, 0.3, 1.0)


def block():
	"""Guarded hit: duller clang with a thud."""
	b = np.zeros(int(0.7 * SR))
	place(b, band_noise(0.06, 300, 5000) * env_exp(0.06, 0.0008, 0.02), 0.0, 0.8)
	place(b, metal(note(7), 0.5, 0.09), 0.0, 0.5)
	t = t_axis(0.15)
	place(b, np.sin(2 * np.pi * (110 * np.exp(-t * 10) + 60) * t) * np.exp(-t / 0.04), 0.0, 0.6)
	return reverb(b, 0.15, 0.5)


def guard_break():
	"""Guard shattered: crack, low thump and a falling glass line."""
	b = np.zeros(int(1.6 * SR))
	place(b, band_noise(0.15, 800, 14000) * env_exp(0.15, 0.0008, 0.04), 0.0, 0.9)
	place(b, metal(note(2), 0.8, 0.2), 0.0, 0.5)
	for i, st in enumerate([24, 19, 15]):
		place(b, glass(note(st), 0.6, decay=0.2, bright=0.5), 0.08 + i * 0.09, 0.35)
	return reverb(b, 0.3, 1.0)


def stagger():
	"""Mob reels: descending wobble tone with a soft crunch."""
	t = t_axis(0.7)
	f = note(12) * (1.0 - 0.35 * t / 0.7) * (1 + 0.02 * np.sin(2 * np.pi * 14 * t))
	b = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_adsr(0.7, 0.01, 0.2, 0.5, 0.4) * 0.5
	place(b, band_noise(0.08, 400, 6000) * env_exp(0.08, 0.001, 0.025), 0.0, 0.5)
	return reverb(b, 0.2, 0.6)


def boss_roar():
	"""Floor Guardian roar (engage, enrage): a low growl with a throat sweep
	over a stone rumble. Original synthesis, pitched for a four-metre body."""
	dur = 1.6
	t = t_axis(dur)
	f0 = 70.0 * (1.0 + 0.35 * np.exp(-t * 3.0)) * (1.0 - 0.15 * t / dur)
	vib = 1.0 + 0.03 * np.sin(2 * np.pi * 9.0 * t)
	phase = 2 * np.pi * np.cumsum(f0 * vib) / SR
	growl = np.zeros_like(t)
	for k in range(1, 12):
		growl += np.sin(phase * k + RNG.uniform(0, 6.28)) / k ** 0.8
	growl *= env_adsr(dur, 0.06, 0.4, 0.55, 0.6)
	breath = sweep_noise(dur, 900, 350, 0.6) * env_adsr(dur, 0.05, 0.3, 0.5, 0.6)
	b = growl * 0.7 + breath * 0.5
	place(b, band_noise(0.25, 40, 200) * env_exp(0.25, 0.002, 0.08), 0.0, 0.9)
	return reverb(b, 0.35, 1.6, damp=3000.0)


def boss_charge():
	"""Charge telegraph: a rising rumble under a whoosh, claws scraping stone."""
	dur = 0.9
	t = t_axis(dur)
	rumble = one_pole_lp(noise(dur), 220) * (0.3 + 0.7 * t / dur)
	whoosh = sweep_noise(dur, 300, 2400, 0.5) * env_adsr(dur, 0.2, 0.2, 0.9, 0.25)
	b = rumble * 1.2 + whoosh * 0.5
	for k in range(6):
		place(b, band_noise(0.06, 800, 5000) * env_exp(0.06, 0.001, 0.02), 0.1 + k * 0.13, 0.25)
	return reverb(b, 0.25, 1.2, damp=4000.0)


def brass(freq, dur, a=0.03, r=0.4, bright=2600.0, det=0.06):
	"""Brassy section note: three detuned saws through a swelling low-pass."""
	t = t_axis(dur)
	x = np.zeros_like(t)
	for d in (-det, 0.0, det):
		f = freq * 2.0 ** (d / 12.0)
		x += (2 * ((f * t) % 1.0) - 1) / 3.0
	x = one_pole_lp(x, bright) * 0.6 + one_pole_lp(x, bright * 0.4) * 0.4
	return x * env_adsr(dur, a, 0.12, 0.75, r)


def timpani(freq, dur=1.2):
	t = t_axis(dur)
	f = freq * (1.0 + 0.08 * np.exp(-t * 18.0))
	ph = 2 * np.pi * np.cumsum(f) / SR
	body = (np.sin(ph) + 0.4 * np.sin(ph * 1.5) + 0.2 * np.sin(ph * 1.99)) * np.exp(-t / 0.45)
	hit = band_noise(dur, 60, 900) * env_exp(dur, 0.001, 0.05)
	return body * 0.8 + hit * 0.35


def boss_sting():
	"""Floor Guardian engage stinger: a dissonant low brass stab (A, B-flat,
	E) over a timpani hit, with a rising string-like swell after it."""
	b = np.zeros(int(2.6 * SR))
	for st, g in ((-36, 0.5), (-35, 0.35), (-29, 0.4), (-24, 0.3)):
		place(b, brass(note(st), 1.4, a=0.015, r=0.9, bright=1800.0), 0.0, g)
	place(b, timpani(note(-36)), 0.0, 0.9)
	place(b, timpani(note(-36)), 0.38, 0.6)
	t = t_axis(1.6)
	swell = np.zeros_like(t)
	for st in (-12, -11, -5):
		f = note(st) * (1.0 + 0.04 * t / 1.6)
		swell += (2 * ((f * t) % 1.0) - 1) * 0.06
	place(b, one_pole_lp(swell, 1500) * env_adsr(1.6, 0.9, 0.2, 0.8, 0.5), 0.6, 1.0)
	return reverb(b, 0.35, 1.8, damp=4000.0)


def boss_phase_sting():
	"""Last bar / weapon swap: brass climbing a half step at a time into a
	held cluster, two timpani hits, a cymbal-ish wash."""
	b = np.zeros(int(2.4 * SR))
	for i, st in enumerate((-31, -30, -29, -28)):
		place(b, brass(note(st), 0.32, a=0.01, r=0.12, bright=2200.0), i * 0.14, 0.45)
	for st, g in ((-24, 0.4), (-23, 0.3), (-17, 0.35)):
		place(b, brass(note(st), 1.3, a=0.02, r=0.8, bright=3000.0), 0.56, g)
	place(b, timpani(note(-31)), 0.56, 0.9)
	place(b, timpani(note(-31)), 0.7, 0.6)
	place(b, band_noise(1.4, 3000, 12000) * env_exp(1.4, 0.01, 0.4), 0.56, 0.18)
	return reverb(b, 0.35, 1.6, damp=5000.0)


def floor_victory():
	"""Floor cleared fanfare (the "Congratulations" moment): a brass call
	A-C#-E-A rising into a held A major chord, glass sparkles on top."""
	b = np.zeros(int(4.2 * SR))
	call = [(-12, 0.0, 0.18), (-8, 0.18, 0.18), (-5, 0.36, 0.18), (0, 0.54, 0.5),
		(-3, 1.08, 0.16), (0, 1.26, 0.16)]
	for st, at, d in call:
		place(b, brass(note(st), d + 0.12, a=0.01, r=0.1, bright=3400.0), at, 0.4)
		place(b, brass(note(st - 12), d + 0.12, a=0.01, r=0.1, bright=2000.0), at, 0.22)
	for st in (-24, -12, -8, -5, 0, 4):
		place(b, brass(note(st), 2.6, a=0.04, r=1.4, bright=3200.0), 1.44, 0.2)
	place(b, timpani(note(-24)), 1.44, 0.7)
	place(b, _arp([24, 28, 31, 36, 40, 43, 48], 0.06, 0.18, 0.3), 1.5, 1.0)
	for k in range(26):
		place(b, glass(note(36 + RNG.integers(0, 14)), 0.3, decay=0.06, bright=0.3), 1.6 + k * 0.05, 0.08)
	return reverb(b, 0.38, 2.0)


def last_attack():
	"""Last Attack bonus: a bright bell strike, a fast rising glass run and a
	ringing high chord (pitched above level_up so the two never blur)."""
	b = np.zeros(int(2.4 * SR))
	place(b, fm_bell(note(12), 1.8, index=3.0, ratio=3.5, decay=0.7), 0.0, 0.45)
	place(b, _arp([24, 28, 31, 36, 40, 43, 48, 52], 0.035, 0.12, 0.35), 0.05, 1.0)
	chord = sum(glass(note(st), 1.8, decay=0.7) for st in (36, 40, 43, 48))
	place(b, chord, 0.36, 0.3)
	place(b, band_noise(0.8, 8000, 16000) * env_exp(0.8, 0.05, 0.25), 0.3, 0.06)
	return reverb(b, 0.4, 1.6)


RECIPES = {
	"boss_roar": boss_roar, "boss_charge": boss_charge,
	"boss_sting": boss_sting, "boss_phase_sting": boss_phase_sting, "floor_victory": floor_victory, "last_attack": last_attack,
	"parry": parry, "block": block, "guard_break": guard_break, "stagger": stagger,
	"menu_open": menu_open, "menu_close": menu_close, "menu_select": menu_select,
	"menu_confirm": menu_confirm, "menu_back": menu_back, "menu_error": menu_error,
	"panel_slide": panel_slide, "notify": notify, "party_invite": party_invite,
	"item_get": item_get, "item_rare": item_rare, "level_up": level_up,
	"quest_accept": quest_accept, "quest_complete": quest_complete,
	"hit_digital": hit_digital, "crit_digital": crit_digital,
	"shatter": shatter, "shatter_boss": shatter_boss, "player_death": player_death,
	"respawn": respawn, "heartbeat": heartbeat, "realm_announce": realm_announce,
	"skill_charge": skill_charge,
}


def write_ogg(path, x):
	pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
	with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
		wav_path = tmp.name
	with wave.open(wav_path, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(pcm.tobytes())
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
	os.unlink(wav_path)


def main():
	here = os.path.dirname(os.path.abspath(__file__))
	out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "assets", "audio", "crystal")
	only = set(sys.argv[2:])
	os.makedirs(out, exist_ok=True)
	for name, fn in RECIPES.items():
		if only and name not in only:
			continue
		x = fn()
		if name != "heartbeat":
			x = finish(x)
		write_ogg(os.path.join(out, name + ".ogg"), x)
		print(f"{name:16s} {len(x) / SR:5.2f}s")


if __name__ == "__main__":
	main()
