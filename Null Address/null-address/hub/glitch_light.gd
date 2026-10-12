extends OmniLight3D

## Glitch light for the HUB doorway.
##
## Not a smooth flicker - a DIGITAL fault. The light jumps between discrete
## brightness levels on a stuttering rhythm, strobing hard on some frames and
## holding dead black on others, with the colour shifting toward a cold sick
## cyan-white so it reads as a broken sign rather than a failing bulb.
##
## Use this instead of flicker_light.gd when the fixture should feel WRONG
## rather than merely old. Attach directly to an OmniLight3D.
##
## Every value is exported so two glitch lights can be given different rhythms.

@export_group("Glitch")
@export var glitch_enabled := true
## Peak energy. The light is scaled DOWN from here, never above.
@export var base_energy := 4.0
## How many discrete brightness jumps per second. Higher = more frantic.
@export var steps_per_second := 14.0
## How far it drops. 1.0 means some steps are fully black.
@export_range(0.0, 1.0) var depth := 0.85
## Chance any given step is a full blackout rather than a dim step.
@export_range(0.0, 1.0) var blackout_chance := 0.28
## Chance a step holds the previous value instead of jumping - this stutter is
## what makes it read as a digital fault rather than a random strobe.
@export_range(0.0, 1.0) var hold_chance := 0.22

@export_group("Colour")
## Colour at full brightness.
@export var color_bright := Color(0.82, 0.95, 1.00)
## Colour in the dip - pushed toward a sickly green-cyan.
@export var color_dim := Color(0.25, 0.65, 0.55)
## How fast the colour chases the brightness change.
@export var color_speed := 18.0

@export_group("Rhythm")
## Offset this light's rhythm so neighbouring fixtures do not sync.
@export var phase_offset := 0.0
## Seconds between the light settling and the next burst of glitching.
@export var calm_min := 0.4
@export var calm_max := 2.6
## Multiplies steps_per_second during a burst.
@export var burst_speed_scale := 2.2

var _t := 0.0
var _step := 0
var _level := 1.0
var _burst := 0.0
var _calm := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_t = phase_offset
	_rng.seed = int(phase_offset * 1000.0) + 7919
	light_energy = base_energy
	light_color = color_bright
	if not glitch_enabled:
		set_process(false)


func _process(delta: float) -> void:
	_t += delta
	_burst -= delta
	if _burst <= 0.0:
		# resting between bursts: settle to a dim, steady glow
		_calm -= delta
		if _calm <= 0.0:
			_burst = _rng.randf_range(0.25, 1.1)
			_calm = _rng.randf_range(calm_min, calm_max)
		_apply_level(0.16, delta)
		return

	# in a burst: step the brightness on a fixed clock
	var rate := steps_per_second * burst_speed_scale
	var target := float(_step) / maxf(rate, 0.001)
	if _t >= target:
		_step += 1
		_next_level()
	_apply_level(_level, delta)


func _next_level() -> void:
	if _rng.randf() < hold_chance:
		return                      # stutter: keep the current level
	if _rng.randf() < blackout_chance:
		_level = 0.0                # hard cut
	else:
		_level = _rng.randf_range(1.0 - depth, 1.0)


func _apply_level(level: float, delta: float) -> void:
	# energy snaps, colour eases - a snapping colour looks like a rendering
	# bug rather than a light
	light_energy = base_energy * level
	var want := color_bright.lerp(color_dim, 1.0 - level)
	light_color = light_color.lerp(want, clampf(color_speed * delta, 0.0, 1.0))


## Force a burst now, e.g. when the player steps into the trigger.
func trigger_burst() -> void:
	_burst = 1.4
	_calm = 0.0
