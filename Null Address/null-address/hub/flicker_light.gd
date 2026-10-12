extends OmniLight3D

## Failing-fluorescent light for Null Address.
##
## Mostly lit, with a slow breathing dip, a fast shimmer, and occasional hard
## dropouts so the lights feel like they are barely holding on. Every value is
## exported so each fixture can be tuned to its own rhythm — a corridor where
## every light stutters in sync reads as a bug, not as dread.
##
## Attach directly to an OmniLight3D node.

@export_group("Flicker")
## Turn the flicker off to get a steady light.
@export var flicker_enabled := true
## Peak energy. The light is multiplied down from here, never above.
@export var base_energy := 2.2
## Speed of the fast shimmer.
@export var flicker_speed := 8.0
## How far the light dips (0 = steady, 1 = dips to nothing on the slow cycle).
@export_range(0.0, 1.0) var flicker_depth := 0.35
## Average number of hard dropouts per second. 0 disables them.
@export var dropout_rate := 0.35
## Shortest and longest dropout duration, in seconds.
@export var dropout_min := 0.03
@export var dropout_max := 0.16
## Multiplies the energy while a dropout is active.
@export_range(0.0, 1.0) var dropout_energy := 0.04

@export_group("Phase")
## Offset this light's rhythm so neighbouring fixtures do not sync up.
@export var phase_offset := 0.0

var _t := 0.0
var _drop_timer := 0.0


func _ready() -> void:
	_t = phase_offset
	light_energy = base_energy


func _process(delta: float) -> void:
	if not flicker_enabled:
		return

	_t += delta

	if _drop_timer > 0.0:
		_drop_timer -= delta
		light_energy = base_energy * dropout_energy
		return

	# Slow breath + fast shimmer, blended.
	var slow := sin(_t * 1.7) * 0.5 + 0.5
	var fast := sin(_t * flicker_speed * 3.1) * 0.5 + 0.5
	var level := 1.0 - flicker_depth * (slow * 0.45 + fast * 0.55)
	light_energy = base_energy * maxf(level, 0.0)

	if dropout_rate > 0.0 and randf() < dropout_rate * delta:
		_drop_timer = randf_range(dropout_min, dropout_max)
