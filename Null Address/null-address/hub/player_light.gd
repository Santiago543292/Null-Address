extends OmniLight3D

## Player light.
##
## A weak, short-range light that travels with the player. Its only job is to
## lift the shadows within a couple of metres so the environment is readable —
## decay, floor, obstacles — without lighting the room and killing the dread.
##
## Kept deliberately: no shadow casting (a moving shadow-caster looks wrong and
## costs a shadow pass per frame), warm-neutral so it does not tint the scene,
## and its energy breathes very slowly so it feels like a handheld torch rather
## than a light source.

@export var base_energy := 0.9
## Metres. Short on purpose: past this, the dark wins.
@export var reach := 7.0
## Depth of the slow breathing (0 = steady).
@export_range(0.0, 1.0) var breath := 0.12
@export var breath_rate := 0.35

var _t := 0.0


func _ready() -> void:
	light_color = Color(0.86, 0.88, 0.92)
	omni_range = reach
	omni_attenuation = 1.6
	shadow_enabled = false
	light_energy = base_energy


func _process(delta: float) -> void:
	_t += delta
	light_energy = base_energy * (1.0 - breath * (0.5 + 0.5 * sin(_t * breath_rate * TAU)))
