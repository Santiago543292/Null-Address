extends Node3D

## The ACT door that rises out of the ground.
##
## Starts buried below the floor. When the player enters the glitch zone it
## grinds up out of the ground, the area around it corrupts, and the door
## becomes usable.
##
## Attach to the door's root (the Node3D holding the doorway mesh, pillars,
## slab, sign and lights).
##
## WHY A SCRIPT AND NOT AN ANIMATION
## The rise has to interact with gameplay state (has the player seen it, are
## they inside the zone), so driving it from code keeps one source of truth.
## The motion itself is a tween - no AnimationPlayer resource to keep in sync.

@export_group("Placement")
## Take the place of a lamp when it rises, so it looks like a lamp became the
## door. Set by LampPuzzle; leave empty to stay where the scene put it.
@export var spawn_at_lamp := ""

@export_group("Rise")
## How far below its final position the door starts, in metres. Should be
## deeper than the door is tall so it is fully hidden.
@export var buried_depth := 4.2
## Seconds the rise takes.
@export var rise_seconds := 3.4
## Ease the rise so it starts slow and settles, rather than moving linearly.
@export var rise_transition := Tween.TRANS_CUBIC
@export var rise_ease := Tween.EASE_OUT
## Shake the whole structure while it rises.
@export var shake_amount := 0.055
@export var shake_speed := 26.0

@export_group("Behaviour")
## Rise automatically when the glitch zone is entered.
@export var rise_on_trigger := true
## Leave the door buried until the player has actually looked at the zone.
## This is the "you see it, then it comes up" beat.
@export var require_player_to_look := true
## Once risen, never bury it again for this session.
@export var one_way := true

@export_group("Pull")
## Once risen, drag the player in when they get this close, like a black hole.
## The pull is DISABLED by default. The design is that the player is never
## dragged - they walk into the door because they want to. The glitches and the
## watcher do the persuading.
##
## Set this true only for a deliberate scripted grab; the escalation no longer
## depends on it.
@export var pull_enabled := false
## Seconds the door stands there doing nothing before the pull starts. This is
## the window where the world is glitching and the music is climbing - the
## player gets to watch it happen before they are taken.
## Seconds between the door finishing its rise and the pull engaging. Must be
## LONGER than the escalation's ramp, or the door grabs the player before the
## world has finished falling apart and they never see the worst of it.
@export var pull_delay := 15.0
## Distance at which the pull starts, in metres. Large on purpose: once the
## door is up it should drag the player in from anywhere on the field, not only
## when they are standing on top of it. 4.5m meant the player could watch from
## ten metres away and never feel anything.
@export var pull_radius := 60.0
## Distance at which the pull is strongest.
@export var pull_core_radius := 1.6
## Let the player pass through geometry while being dragged. Without this the
## pull drives them into a wall and they stick there - the door's grip and the
## wall's collision fight, and the wall wins.
@export var phase_while_pulling := true

## Peak pull speed, in metres per second. Must beat the player's walk speed or
## they can walk back out - the whole point is that they cannot.
##
## The controller LERPS velocity toward the movement input, so a value only a
## little above walking speed gets bled off before it moves anything. This is
## set well clear of that.
@export var pull_strength := 26.0
## Seconds of overwhelming pull before the act loads, so the player feels it
## take them rather than being teleported.
@export var consume_seconds := 1.1
## How hard the camera shakes as they are taken.
@export var consume_shake := 0.09

@export_group("Glitch")
## Flicker the door's own visibility while it rises, so it phases in.
@export var glitch_while_rising := true
## How often to snap the door visible/invisible during the rise, per second.
@export var glitch_rate := 18.0

signal risen()

var _home := Vector3.ZERO
var _buried := Vector3.ZERO
var _rising := false
var _done := false
var _t := 0.0
var _glitch_accum := 0.0
var _rng := RandomNumberGenerator.new()
var _meshes: Array[Node3D] = []
var _zone: Area3D
var _player: CharacterBody3D
var _pulling := false
var _consumed := false
var _consume_t := 0.0
var _pull_armed := false
var _arm_t := 0.0
var _saved_mask := -1


func _ready() -> void:
	# if we are standing in for a lamp, move onto it first
	if spawn_at_lamp != "":
		var lamps := get_parent().get_node_or_null("LampPosts")
		if lamps != null:
			var lamp := lamps.get_node_or_null(spawn_at_lamp)
			if lamp is Node3D:
				global_position = (lamp as Node3D).global_position
				_home = position
	_home = position
	_buried = _home - Vector3(0, buried_depth, 0)
	position = _buried
	_rng.randomize()
	_collect_meshes()
	_find_zone()


## Every visual child that should phase during the rise. Excludes lights so the
## glow stays readable while the geometry flickers.
func _collect_meshes() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			_meshes.append(c)
		elif c is Node3D and not (c is OmniLight3D):
			for g in c.get_children():
				if g is MeshInstance3D:
					_meshes.append(g)


func _find_player() -> CharacterBody3D:
	# the player is the only CharacterBody3D in the hub
	var root := get_tree().current_scene
	if root == null:
		return null
	return _find_body(root)


func _find_body(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D:
		return n
	for c in n.get_children():
		var f := _find_body(c)
		if f != null:
			return f
	return null


func _find_zone() -> void:
	# the glitch zone is a sibling Area3D named GlitchZone
	var parent := get_parent()
	if parent == null:
		return
	_zone = parent.get_node_or_null("GlitchZone") as Area3D
	if _zone == null:
		return
	_zone.body_entered.connect(_on_zone_enter)


func _on_zone_enter(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if _done and one_way:
		return
	if not rise_on_trigger:
		return
	if require_player_to_look and not _player_is_looking(body):
		# they are in the zone but facing away - wait for them to turn
		return
	rise()


## Is the player's camera pointing at this door?
func _player_is_looking(body: Node3D) -> bool:
	var cam := _find_camera(body)
	if cam == null:
		return true          # no camera to judge by - do not block the beat
	return cam.is_position_in_frustum(global_position + Vector3(0, 1.4, 0))


func _find_camera(n: Node) -> Camera3D:
	if n is Camera3D:
		return n
	for c in n.get_children():
		var f := _find_camera(c)
		if f != null:
			return f
	return null


## Start the rise. Safe to call more than once.
func rise() -> void:
	if _rising or (_done and one_way):
		return
	_rising = true
	_done = true

	var tween := create_tween()
	tween.set_trans(rise_transition).set_ease(rise_ease)
	tween.tween_property(self, "position", _home, rise_seconds)
	tween.finished.connect(_on_rise_finished)


func _process(delta: float) -> void:
	_t += delta

	_tick_consume(delta)

	# The pull is gated on the door being UP, and then on a further pull_delay
	# so the world has time to visibly fall apart while the player watches.
	#
	# Two separate bugs lived here: `if _arm_t > 0.0` was false on the first
	# frame (_arm_t starts at 0.0) so the countdown was skipped entirely, and
	# nothing checked whether the door had risen - so the pull could engage
	# before there was anything to be pulled toward.
	if not (_done and not _rising):
		return

	if not _pull_armed:
		_arm_t -= delta
		if _arm_t > 0.0:
			return
		_pull_armed = true

	if _player != null and _player.is_inside_tree():
		_apply_pull(delta)

	if _rising:
		# grind: shake the structure while it climbs
		var s := shake_amount * (1.0 - _rise_progress())
		position.x = _home.x + sin(_t * shake_speed) * s
		position.z = _home.z + cos(_t * shake_speed * 0.7) * s

		if glitch_while_rising:
			_glitch_accum += delta * glitch_rate
			if _glitch_accum >= 1.0:
				_glitch_accum = 0.0
				_phase_meshes()


func _rise_progress() -> float:
	var climbed := position.y - _buried.y
	return clampf(climbed / maxf(buried_depth, 0.001), 0.0, 1.0)


## Snap the geometry visible/invisible for one frame.
func _phase_meshes() -> void:
	var show := _rng.randf() > 0.35
	for m in _meshes:
		if is_instance_valid(m):
			m.visible = show


func _on_rise_finished() -> void:
	_rising = false
	position = _home
	for m in _meshes:
		if is_instance_valid(m):
			m.visible = true
	# now the door exists, the area can properly corrupt
	if _zone != null and _zone.has_method("enable_full_glitch"):
		_zone.call("enable_full_glitch")
	_player = _find_player()
	# hold the pull back so the escalation has time to show itself
	_arm_t = pull_delay
	_pull_armed = false
	risen.emit()


## Drag the player toward the door and, once they are close enough, take them.
func _apply_pull(delta: float) -> void:
	if not pull_enabled or _player == null or not is_instance_valid(_player):
		return
	if not _player.is_inside_tree():
		return
	var target := global_position + Vector3(0, 1.0, 0)
	var to_door := target - _player.global_position
	to_door.y = 0.0
	var dist := to_door.length()

	if dist > pull_radius:
		return
	if not _pulling:
		_pulling = true
		_begin_phase()

	# ramp the pull up as they get closer - weak at the rim, inescapable at the
	# core, so it feels like being drawn in rather than shoved
	var t := clampf(
		inverse_lerp(pull_radius, pull_core_radius, dist), 0.0, 1.0)
	var speed := lerpf(pull_strength * 0.35, pull_strength, t)

	var dir := to_door.normalized()
	_player.velocity.x = dir.x * speed
	_player.velocity.z = dir.z * speed
	# hold them on the ground while being dragged
	if _player.is_on_floor():
		_player.velocity.y = 0.0

	# While phasing, drive the position directly as well. Velocity alone still
	# lets the controller's own collision resolve them out of a wall; moving the
	# transform guarantees the pull actually closes the distance.
	if phase_while_pulling and _player.is_inside_tree():
		var step := speed * delta
		_player.global_position = _player.global_position.move_toward(
			Vector3(target.x, _player.global_position.y, target.z), step)

	if dist <= pull_core_radius and not _consumed:
		_consumed = true
		_consume_t = consume_seconds
		# the music closes over them
		var pm := get_node_or_null("ProximityMusic")
		if pm != null and pm.has_method("swell"):
			pm.call("swell")


## Shake the camera while being consumed, then hand off to the act.
func _tick_consume(delta: float) -> void:
	if not _consumed:
		return
	_consume_t -= delta
	var cam := _find_camera(_player) if _player != null else null
	if cam != null:
		cam.h_offset = sin(_t * 60.0) * consume_shake
		cam.v_offset = cos(_t * 71.0) * consume_shake
	if _consume_t <= 0.0:
		var logic := get_node_or_null("DoorLogic")
		if logic != null and logic.has_method("resolve_target"):
			var path: String = logic.call("resolve_target")
			if path != "":
				var na: String = str(logic.get("next_act"))
				if na != "":
					GameState.current_act = na
				GameState.set_gameplay_mouse(true)
				get_tree().change_scene_to_file(path)


## Has the door finished rising?
## Stop the player's body colliding with the world, so the pull cannot wedge
## them inside a building. The mask is restored when the pull ends.
func _begin_phase() -> void:
	if not phase_while_pulling or _player == null:
		return
	_saved_mask = _player.collision_mask
	_player.collision_mask = 0


func _end_phase() -> void:
	if _player == null or not is_valid_phase():
		return
	_player.collision_mask = _saved_mask


func is_valid_phase() -> bool:
	return _saved_mask >= 0 and _player != null


func is_risen() -> bool:
	return _done and not _rising


## Put the door back in the ground. For testing the beat again.
func reset() -> void:
	_rising = false
	_done = false
	position = _buried
	for m in _meshes:
		if is_instance_valid(m):
			m.visible = true
