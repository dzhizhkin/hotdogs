#!/usr/bin/env python3
"""Синтезирует мультяшные звуки игры в assets/audio/sfx/*.wav.

Всё генерируется формулами, внешних сэмплов нет. Запуск: python3 tools/gen_sfx.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")

rng = random.Random(7)


def env(t, attack, length):
	"""Быстрая атака и экспоненциальное затухание к концу звука."""
	if t < attack:
		return t / attack
	return math.exp(-5.0 * (t - attack) / max(length - attack, 1e-6))


def sweep(f0, f1, length, wave_fn=math.sin, attack=0.005, vibrato=0.0):
	out = []
	phase = 0.0
	n = int(length * RATE)
	for i in range(n):
		t = i / RATE
		k = t / length
		f = f0 * (f1 / f0) ** k
		f *= 1.0 + vibrato * math.sin(TAU * 18.0 * t)
		phase += TAU * f / RATE
		out.append(wave_fn(phase) * env(t, attack, length))
	return out


def noise(length, cutoff, attack=0.002, decay=5.0):
	"""Шум через однополюсный ФНЧ: чем ниже cutoff, тем глуше."""
	out = []
	a = math.exp(-TAU * cutoff / RATE)
	y = 0.0
	n = int(length * RATE)
	for i in range(n):
		t = i / RATE
		y = (1 - a) * (rng.uniform(-1, 1)) + a * y
		e = t / attack if t < attack else math.exp(-decay * (t - attack) / length)
		out.append(y * e)
	return out


def mix(*tracks):
	n = max(len(tr) for tr, _ in tracks)
	out = [0.0] * n
	for tr, gain in tracks:
		for i, s in enumerate(tr):
			out[i] += s * gain
	return out


def concat(*parts):
	out = []
	for p in parts:
		out.extend(p)
	return out


def silence(length):
	return [0.0] * int(length * RATE)


def triangle(phase):
	return 2.0 / math.pi * math.asin(math.sin(phase))


def square(phase):
	# Смягчённый меандр: без резких ступенек, чтобы не резал слух
	return math.tanh(4.0 * math.sin(phase))


def save(name, samples, peak=0.8):
	top = max(abs(s) for s in samples) or 1.0
	# Короткий спад в конце убирает щелчок обрыва
	fade = min(len(samples), int(0.004 * RATE))
	for i in range(fade):
		samples[-1 - i] *= i / fade
	path = os.path.join(OUT, name + ".wav")
	with wave.open(path, "wb") as f:
		f.setnchannels(1)
		f.setsampwidth(2)
		f.setframerate(RATE)
		f.writeframes(b"".join(struct.pack("<h", int(s / top * peak * 32767)) for s in samples))


TAU = math.tau


def step():
	# Мягкий шлепок лапкой: глухой шум и низкий тон
	return mix((noise(0.07, 900, decay=7.0), 1.0), (sweep(180, 90, 0.07), 0.5))


def jump():
	# Пружинка вверх
	return sweep(220, 640, 0.2, triangle, vibrato=0.03)


def land():
	return mix((noise(0.12, 600, decay=6.0), 0.8), (sweep(130, 55, 0.14), 1.0))


def bonk():
	# Удар хлебной палочкой: деревянный стук из двух затухающих частот
	t1 = sweep(320, 300, 0.25)
	t2 = sweep(760, 740, 0.12)
	click = noise(0.015, 5000)
	return mix((t1, 1.0), (t2, 0.6), (click, 0.5), (sweep(500, 180, 0.3, triangle, vibrato=0.05), 0.4))


def fall():
	# Свист падения в пропасть
	return sweep(1100, 220, 0.9, math.sin, attack=0.05, vibrato=0.01)


def pop():
	# Возрождение: пузырёк
	return mix((sweep(300, 1200, 0.08), 1.0), (noise(0.02, 3000), 0.3))


def squish():
	# Сосиска плюхается в булочку: влажный шлёп с плывущим тоном
	return mix((noise(0.25, 700, decay=4.0), 0.9), (sweep(260, 90, 0.25, triangle, vibrato=0.08), 0.7))


def mayo():
	# Майонез из бутылки, ~3 с: пульсирующий хлюпающий шум
	length = 3.1
	base = noise(length, 1400, attack=0.05, decay=0.6)
	out = []
	for i, s in enumerate(base):
		t = i / RATE
		pulse = 0.55 + 0.45 * math.sin(TAU * 7.0 * t + 1.5 * math.sin(TAU * 1.3 * t))
		out.append(s * pulse)
	gurgle = sweep(140, 110, length, triangle, attack=0.1, vibrato=0.2)
	return mix((out, 1.0), (gurgle, 0.15))


def giggle():
	# «Хи-хи-хи»: короткие писки с вибрато, каждый чуть ниже
	parts = []
	for i, f in enumerate([980, 900, 860, 780, 720]):
		parts.append(sweep(f, f * 1.15, 0.09, triangle, vibrato=0.06))
		parts.append(silence(0.05 + 0.01 * i))
	return concat(*parts)


def fanfare():
	# Короткое «та-да»: арпеджио до-ми-соль и аккорд
	notes = [523.25, 659.25, 783.99]
	parts = [sweep(f, f, 0.12, square, attack=0.004) for f in notes]
	chord = mix(*[(sweep(f, f, 0.9, square, attack=0.01), 0.5) for f in notes + [1046.5]])
	return concat(*parts, chord)


def whistle():
	# Свисток старта гонки с трелью
	out = []
	length = 0.55
	phase = 0.0
	for i in range(int(length * RATE)):
		t = i / RATE
		f = 2100 * (1.0 + 0.04 * math.sin(TAU * 28.0 * t))
		phase += TAU * f / RATE
		e = min(t / 0.02, 1.0) * min((length - t) / 0.08, 1.0)
		out.append(math.sin(phase) * e)
	return mix((out, 1.0), (noise(length, 4000, decay=1.0), 0.15))


def click():
	return mix((sweep(1500, 900, 0.035), 1.0), (noise(0.01, 6000), 0.4))


def countdown():
	# Чёткий короткий сигнал, чтобы не спутать его со стартовым свистком.
	return mix((sweep(660, 660, 0.18), 1.0), (sweep(1320, 1320, 0.08), 0.3))


SOUNDS = {
	"step": (step, 0.5),
	"jump": (jump, 0.6),
	"land": (land, 0.6),
	"bonk": (bonk, 0.8),
	"fall": (fall, 0.6),
	"pop": (pop, 0.6),
	"squish": (squish, 0.8),
	"mayo": (mayo, 0.5),
	"giggle": (giggle, 0.6),
	"fanfare": (fanfare, 0.6),
	"whistle": (whistle, 0.5),
	"click": (click, 0.5),
	"countdown": (countdown, 0.6),
}


if __name__ == "__main__":
	os.makedirs(OUT, exist_ok=True)
	for name, (fn, peak) in SOUNDS.items():
		save(name, fn(), peak)
		print(name)
