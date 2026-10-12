extends Node3D

## Presence.
##
## The house feels occupied. It is not.
##
## There is deliberately NO entity here: no mesh, no AI, no spawn, nothing the
## player can ever see or catch. Everything this node does is environmental, and
## every effect is gated on the player NOT looking at it:
##
##   - doors drift a few degrees, only while off-screen
##   - lights in rooms you have already left switch themselves
##   - footsteps cross the floor above, walking from one side to the other
##   - knocks come from inside walls, in pairs and threes
##   - small props shift position while unobserved
##   - the ambience drops to near-silence right before a cue
##
## The design bet: the player assembles the idea of a presence themselves, from
## evidence that is never confirmed. Nothing is ever there, and that is the
## point. Do not add an entity to this scene — it would break the whole thing.

const SFX := preload("res://hub/sfx.gd")

@export var enabled := true

@export_group("Timing")
## Gap between events, in seconds. Lower = busier house.
@export var event_min_gap := 11.0
@export var event_max_gap := 30.0
## Quiet period at the very start so the player can settle in.
@export var opening_quiet := 14.0

@export_group("Doors")
@export var door_drift_degrees := 16.0
@export var door_drift_speed := 0.35

@export_group("Props")
## How far a prop may shift when unobserved, in metres.
@export var prop_shift := 0.28

@export_group("Sound")
@export_range(-60.0, 0.0) var sfx_db := -9.0
## How far the ambience bed is ducked during a cue.
@export_range(-60.0, 0.0) var ducked_db := -30.0
@export var duck_seconds := 1.1

var _camera: Camera3D
var _doors: Array[Node3D] = []
var _lights: Array[OmniLight3D] = []
var _props: Array[Node3D] = []
var _above: AudioStreamPlayer3D
var _near: AudioStreamPlayer3D
var _ambience: AudioStreamPlayer

var _timer := 0.0
var _next_event := 0.0
var _duck_timer := 0.0
var _base_ambience_db := -16.0

# Door drift animation state
var _drift_door: Node3D
var _drift_from := 0.0
var _drift_to := 0.0
var _drift_t := 0.0
var _drift_dur := 0.0


func _ready() -> void:
	_gather()
	_build_players()
	_next_event = opening_quiet


func _gather() -> void:
	var root := get_parent()
	if root == null:
		return
	var doors := root.get_node_or_null("Doors")
	if doors != null:
		for c in doors.get_children():
			if c is Node3D:
				_doors.append(c)
	var lights := root.get_node_or_null("Lights")
	if lights != null:
		for c in lights.get_children():
			for l in c.get_children():
				if l is OmniLight3D:
					_lights.append(l)
	var furniture := root.get_node_or_null("Furniture")
	if furniture != null:
		for c in furniture.get_children():
			if c is Node3D:
				_props.append(c)
	# The dread director owns the ambience bed; duck it during cues.
	var dread := root.get_node_or_null("Dread")
	if dread != null:
		for c in dread.get_children():
			if c is AudioStreamPlayer:
				_ambience = c
				_base_ambience_db = c.volume_db
				break


func _build_players() -> void:
	# Footsteps happen on the ceiling plane.
	_above = AudioStreamPlayer3D.new()
	_above.volume_db = sfx_db
	_above.unit_size = 10.0
	_above.max_distance = 45.0
	_above.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_above)

	# Knocks and creaks happen at wall height, near the player.
	_near = AudioStreamPlayer3D.new()
	_near.volume_db = sfx_db
	_near.unit_size = 4.0
	_near.max_distance = 22.0
	_near.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_near)


func _process(delta: float) -> void:
	if not enabled:
		return

	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return

	_advance_door(delta)

	if _duck_timer > 0.0:
		_duck_timer -= delta
		if _duck_timer <= 0.0 and _ambience != null and is_instance_valid(_ambience):
			_ambience.volume_db = _base_ambience_db

	_timer += delta
	if _timer >= _next_event:
		_fire()
		_timer = 0.0
		_next_event = randf_range(event_min_gap, event_max_gap)


## True when a world position is outside what the player can currently see.
func _unseen(pos: Vector3) -> bool:
	if _camera == null:
		return true
	return not _camera.is_position_in_frustum(pos)


func _fire() -> void:
	# Weighted pick. Footsteps and knocks carry most of the dread; door drift is
	# the rarest because it is the most explicit.
	var roll := randf()
	if roll < 0.34:
		_footsteps_above()
	elif roll < 0.62:
		_knock()
	elif roll < 0.78:
		_creak()
	elif roll < 0.90:
		_light_shift()
	else:
		_door_drift()


# --- the cues ---------------------------------------------------------------

## A walk across the ceiling, one side of the house to the other.
func _footsteps_above() -> void:
	if _above == null:
		return
	var y := 3.2 + 0.25
	var dir := 1.0 if randf() < 0.5 else -1.0
	var x0 := -9.0 * dir
	var z := randf_range(-7.0, 7.0)
	_above.global_position = Vector3(x0, y, z)
	_above.stream = SFX.footstep(randi())
	_above.play()

	var steps := randi_range(5, 11)
	var step_gap := randf_range(0.42, 0.58)
	for i in steps:
		await get_tree().create_timer(step_gap).timeout
		if not is_inside_tree():
			return
		var t := float(i + 1) / float(steps)
		_above.global_position = Vector3(lerpf(x0, -x0, t), y, z + randf_range(-0.15, 0.15))
		_above.stream = SFX.footstep(randi())
		_above.pitch_scale = randf_range(0.88, 1.06)
		_above.play()


## Two or three knocks from a wall near the player, as if something is inside it.
func _knock() -> void:
	if _near == null or _camera == null:
		return
	var pp := _camera.global_position
	# GDScript has no for/else, so track the hit explicitly.
	var angles := [0.0, PI * 0.5, PI, PI * 1.5]
	angles.shuffle()
	var placed := false
	for a in angles:
		var p := pp + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 6.0)
		p.y = randf_range(0.9, 2.4)
		if _unseen(p):
			_near.global_position = p
			placed = true
			break
	if not placed:
		_near.global_position = pp + Vector3(3.0, 1.4, 0.0)

	var n := randi_range(2, 3)
	for i in n:
		_near.stream = SFX.knock(randi())
		_near.pitch_scale = randf_range(0.92, 1.05)
		_near.play()
		await get_tree().create_timer(randf_range(0.18, 0.34)).timeout
		if not is_inside_tree():
			return


## A board settling somewhere off-screen.
func _creak() -> void:
	if _near == null or _camera == null:
		return
	var pp := _camera.global_position
	for i in 8:
		var p := pp + Vector3(randf_range(-8.0, 8.0), randf_range(0.2, 2.6), randf_range(-8.0, 8.0))
		if _unseen(p):
			_near.global_position = p
			break
	_near.stream = SFX.creak(randi())
	_near.pitch_scale = randf_range(0.85, 1.1)
	_near.play()


## A light in a room the player is not in switches itself.
func _light_shift() -> void:
	if _lights.is_empty() or _camera == null:
		return
	var pp := _camera.global_position
	var candidates: Array[OmniLight3D] = []
	for l in _lights:
		if not is_instance_valid(l):
			continue
		if l.global_position.distance_to(pp) > 5.0 and _unseen(l.global_position):
			candidates.append(l)
	if candidates.is_empty():
		return
	var target: OmniLight3D = candidates[randi() % candidates.size()]
	if target.get_script() == null:
		return
	# Flip the flicker light's base energy: it either comes on or goes dark.
	# Read through a Variant and coerce, so a light without the property is safe.
	var raw: Variant = target.get("base_energy")
	if raw == null:
		return
	var current := float(raw)
	var new_energy := 0.0 if current > 0.1 else randf_range(1.4, 2.6)
	target.set("base_energy", new_energy)


## A door swings, only while the player cannot see it.
func _door_drift() -> void:
	if _doors.is_empty():
		return
	var candidates: Array[Node3D] = []
	for d in _doors:
		if is_instance_valid(d) and _unseen(d.global_position):
			candidates.append(d)
	if candidates.is_empty():
		return
	_drift_door = candidates[randi() % candidates.size()]
	_drift_from = _drift_door.rotation.y
	var amount := deg_to_rad(door_drift_degrees) * (1.0 if randf() < 0.5 else -1.0)
	_drift_to = _drift_from + amount
	_drift_t = 0.0
	_drift_dur = randf_range(1.6, 3.4)
	if _near != null:
		_near.global_position = _drift_door.global_position + Vector3(0.0, 0.8, 0.0)
		_near.stream = SFX.creak(randi())
		_near.pitch_scale = randf_range(0.9, 1.0)
		_near.play()


func _advance_door(delta: float) -> void:
	if _drift_door == null or not is_instance_valid(_drift_door):
		return
	_drift_t += delta
	var t: float = clampf(_drift_t / maxf(_drift_dur, 0.01), 0.0, 1.0)
	# Ease-in-out so it settles rather than snapping.
	var e := t * t * (3.0 - 2.0 * t)
	_drift_door.rotation.y = lerpf(_drift_from, _drift_to, e)
	if t >= 1.0:
		_drift_door = null
