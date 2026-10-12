extends RefCounted

## Procedural horror SFX.
##
## Builds short 16-bit PCM buffers at runtime instead of shipping .wav files.
## Everything is synthesised: filtered noise for footsteps, a damped low sine
## for knocks, a resonant filter sweep for wood creaks, a falling sine for
## drips, and slow-modulated noise for breath.
##
## Keeping these generated means the house's sound design lives in code and can
## be tuned by changing a number, rather than by finding new audio.

const RATE := 22050


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## Dull footfall. Low-passed noise with a fast decay — the sound of weight
## landing on old boards through a ceiling.
static func footstep(seed_v: int) -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 38.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05)
		out[i] = lp * env
	return _wav(out)


## Knuckle on plasterboard: a low body tone plus a noise transient.
static func knock(seed_v: int) -> AudioStreamWAV:
	var n := int(RATE * 0.30)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 26.0)
		var body := sin(TAU * 78.0 * t) * 0.7
		var noise := rng.randf_range(-1.0, 1.0) * 0.3
		out[i] = (body + noise) * env
	return _wav(out)


## Wood creak: a resonant filter being excited, with the resonance sweeping
## downward so it reads as something heavy settling.
static func creak(seed_v: int) -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var f := 220.0
	var phase := 0.0
	var res := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * clampf(t / 0.9, 0.0, 1.0))
		f = lerpf(f, 150.0, 0.0002)
		phase += TAU * f / RATE
		var exc := rng.randf_range(-1.0, 1.0) * 0.25
		res = res * 0.986 + exc * 0.5
		out[i] = (res + sin(phase) * 0.12) * env * 0.8
	return _wav(out)


## Water drip: a sine whose pitch falls as it decays.
static func drip(seed_v: int) -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 30.0)
		var f := 1400.0 * exp(-t * 12.0)
		out[i] = sin(TAU * f * t) * env * 0.5
	return _wav(out)


## Breath. Not a voice and not words — just slow-modulated filtered noise, which
## is the least information that still reads as "something alive".
static func breath(seed_v: int) -> AudioStreamWAV:
	var n := int(RATE * 1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * clampf(t / 1.4, 0.0, 1.0))
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.02)
		var mod := 0.5 + 0.5 * sin(TAU * 3.2 * t + float(seed_v))
		out[i] = lp * env * mod * 0.5
	return _wav(out)
