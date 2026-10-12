extends Node3D

## Dread director.
##
## The horror here is atmosphere, not a monster: the player is sealed inside a
## boarded-up house and the game's only job is to make them feel like something
## is aware of them. Nothing ever actually attacks. That is the point.
##
## This node:
##   - loops the ambience bed (drips, wind, house noise) from ENTROPYSTARTER
##   - fires one-shot "what was that" cues on a randomized timer
##   - nudges the exposure/fog so the dark creeps in the longer you stay
##   - pushes the heartbeat harder the longer the player goes without progress
##
## Every sound is positional, so cues come from a direction and the player
## turns to look at nothing. That is the whole trick.

@export_group("Ambience")
## Path to the looping ambience bed. Leave empty to skip music entirely.
@export_file("*.wav", "*.ogg", "*.mp3") var ambience_path := "res://Assets/ENTROPYSTARTER/ENTROPYSTARTER/echoes.wav"
@export_range(-60.0, 0.0) var ambience_db := -16.0

@export_group("Cues")
## One-shot sounds fired from random points around the house.
@export_file("*.wav", "*.ogg", "*.mp3") var cue_a := "res://Assets/ENTROPYSTARTER/ENTROPYSTARTER/deja vu.wav"
@export_file("*.wav", "*.ogg", "*.mp3") var cue_b := "res://Assets/ENTROPYSTARTER/ENTROPYSTARTER/internal monologue.wav"
@export_file("*.wav", "*.ogg", "*.mp3") var cue_c := "res://Assets/ENTROPYSTARTER/ENTROPYSTARTER/simulation.wav"
@export var cue_min_gap := 22.0
@export var cue_max_gap := 55.0
@export_range(-60.0, 0.0) var cue_db := -11.0

@export_group("Creep")
## How far the lights dim over time (0 = no dimming).
@export_range(0.0, 1.0) var dim_strength := 0.35
## Seconds of play before the house is fully "awake".
@export var ramp_seconds := 480.0

var _ambience: AudioStreamPlayer
var _cues: Array[AudioStreamPlayer3D] = []
var _cue_paths: Array[String] = []
var _timer := 0.0
var _next_cue := 0.0
var _elapsed := 0.0
var _env: Environment
var _base_ambient := 0.22
var _base_fog := 0.035

# Rooms the cues can come from. Hardcoded to the house layout so a sound is
# never emitted from inside a wall.
const CUE_POINTS: Array[Vector3] = [
	Vector3(-6.0, 1.6, 2.0),    # living room
	Vector3(-4.0, 1.6, -4.5),   # living room back
	Vector3(4.0, 1.6, -4.0),    # kitchen
	Vector3(0.0, 1.6, 4.5),     # hall
	Vector3(7.0, 1.6, 2.5),     # stairs
	Vector3(-4.0, 4.6, -4.0),   # bedroom 1
	Vector3(-4.0, 4.6, 4.0),    # bedroom 2
	Vector3(4.0, 4.6, -3.0),    # storage
	Vector3(2.0, 4.6, 5.0),     # landing
]


func _ready() -> void:
	_env = _find_environment()
	if _env != null:
		_base_ambient = _env.ambient_light_energy
		_base_fog = _env.fog_density

	_start_ambience()
	_build_cue_players()
	_schedule_next_cue()


func _start_ambience() -> void:
	var stream := _load_audio(ambience_path)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = 0
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = stream
	_ambience.volume_db = ambience_db
	_ambience.bus = "Master"
	add_child(_ambience)
	_ambience.play()


func _build_cue_players() -> void:
	for p in [cue_a, cue_b, cue_c]:
		var stream := _load_audio(p)
		if stream == null:
			continue
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.volume_db = cue_db
		player.unit_size = 8.0
		player.max_distance = 40.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_cues.append(player)
		_cue_paths.append(p)


func _load_audio(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _process(delta: float) -> void:
	_elapsed += delta

	# Creep: the house gets darker and thicker the longer you are in it.
	var t: float = clampf(_elapsed / maxf(ramp_seconds, 1.0), 0.0, 1.0)
	if _env != null:
		_env.ambient_light_energy = _base_ambient * (1.0 - dim_strength * t)
		_env.fog_density = _base_fog * (1.0 + 0.9 * t)

	_timer += delta
	if _timer >= _next_cue:
		_fire_cue()
		_schedule_next_cue()


func _schedule_next_cue() -> void:
	_timer = 0.0
	_next_cue = randf_range(cue_min_gap, cue_max_gap)


func _fire_cue() -> void:
	if _cues.is_empty():
		return
	var player: AudioStreamPlayer3D = _cues[randi() % _cues.size()]
	# Drop it at a random room, but never right on top of the player.
	var point: Vector3 = CUE_POINTS[randi() % CUE_POINTS.size()]
	player.global_position = point
	player.pitch_scale = randf_range(0.82, 0.98)   # slow = wrong
	player.play()


func _find_environment() -> Environment:
	var world := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if world == null:
		for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			world = n as WorldEnvironment
			break
	return world.environment if world != null else null
