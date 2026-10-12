extends Node3D

## Camera feel.
##
## Head bob, footstep audio, and a breathing cycle. Attaches under the player
## and drives the Camera3D's local Y offset and roll only — never its X rotation
## or Z distance, because GodoPlayer owns those and would fight back.
##
## Footsteps are synthesised (see sfx.gd) and change character by surface: dull
## on carpet, sharp on boards. The house is all boards, but the parameter is
## here so different floors can be wired later.

const SFX := preload("res://hub/sfx.gd")

@export_group("Bob")
## Vertical travel of the head bob, in metres.
@export var bob_amount := 0.045
## Bob cycles per second at walking pace.
@export var bob_rate := 1.9
## How much the camera rolls side to side while walking.
@export var sway_roll_degrees := 0.55

@export_group("Breath")
## Idle breathing travel, in metres.
@export var breath_amount := 0.012
@export var breath_rate := 0.22

@export_group("Steps")
@export var step_db := -14.0
@export var step_pitch_jitter := 0.08

var _player: CharacterBody3D
var _camera: Camera3D
var _step: AudioStreamPlayer3D

var _bob_phase := 0.0
var _breath_phase := 0.0
var _base_cam_y := 0.0
var _last_step_phase := 0.0


func _ready() -> void:
	_player = _find_body(get_parent())
	if _player == null:
		set_process(false)
		return
	_camera = _find_camera(_player)
	if _camera == null:
		set_process(false)
		return
	_base_cam_y = _camera.position.y

	_step = AudioStreamPlayer3D.new()
	_step.volume_db = step_db
	_step.unit_size = 2.0
	_step.max_distance = 12.0
	_step.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_step)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _camera == null or not is_instance_valid(_camera):
		return

	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var moving := speed > 0.6 and _player.is_on_floor()

	if moving:
		_bob_phase += delta * bob_rate * TAU * clampf(speed / 4.0, 0.6, 1.6)
		# Fire a footstep each time the bob passes through its low point.
		var cycle := fposmod(_bob_phase / TAU, 1.0)
		if cycle < _last_step_phase:
			_play_step()
		_last_step_phase = cycle
	else:
		# Settle the bob back to rest rather than freezing mid-stride.
		_bob_phase = lerpf(_bob_phase, round(_bob_phase / TAU) * TAU, delta * 6.0)

	var bob := sin(_bob_phase) * bob_amount
	var roll := sin(_bob_phase * 0.5) * deg_to_rad(sway_roll_degrees) if moving else 0.0

	# Breathing never stops, but is swamped by the bob while walking.
	_breath_phase += delta * breath_rate * TAU
	var breath := sin(_breath_phase) * breath_amount

	_camera.position.y = _base_cam_y + bob + breath
	_camera.rotation.z = lerpf(_camera.rotation.z, roll, delta * 8.0)


func _play_step() -> void:
	if _step == null:
		return
	_step.stream = SFX.footstep(randi())
	_step.pitch_scale = 1.0 + randf_range(-step_pitch_jitter, step_pitch_jitter)
	_step.global_position = _player.global_position
	_step.play()


func _find_body(node: Node) -> CharacterBody3D:
	if node is CharacterBody3D:
		return node
	for c in node.get_children():
		var f := _find_body(c)
		if f != null:
			return f
	return null


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for c in node.get_children():
		var f := _find_camera(c)
		if f != null:
			return f
	return null
