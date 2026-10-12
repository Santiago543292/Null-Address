extends Area3D
## Mood zone of the PSX Horror Modular Kit demo (bitkiln - https://bitkiln.itch.io): while the player is inside
## the box, level.gd fades the fog, the ambient light and the background to the values below.

@export var fog_color := Color(0.3, 0.3, 0.3)
## Distance where the fog hides everything, in metres.
@export var fog_end := 18.0
@export var ambient_color := Color(0.5, 0.5, 0.5)
@export var ambient_energy := 0.4
## Show the sky (outdoors, rooms with windows) or fill the background with the fog colour.
@export var show_sky := false


func _ready() -> void:
	add_to_group("env_zones")
