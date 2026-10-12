extends Node3D

## Doorway into the house.
##
## Place a trigger in the hub that leads to the next level. Walks the player
## into it and loads the target scene. Deliberately simple: the hub is a
## place, not a menu.

@export_group("Destination")
## Act id from GameState.ACTS ("store", "office", ...). Wins over target_scene.
## Preferred, because it keeps the hub out of the business of knowing paths.
@export var next_act := ""
## Explicit scene path, used when next_act is empty or unknown.
@export_file("*.tscn") var target_scene := "res://Maps/house.tscn"

@export_group("Behaviour")
@export var prompt := "ENTER"
## Seconds the player must stand in the trigger before it fires, so you cannot
## clip through it by accident.
@export var dwell_seconds := 0.8
@export var enabled := true
## Fade to black before loading, so the cut is not a pop.
@export var fade_seconds := 0.6

@export_group("Random Placement")
## Move this door to a random clear spot when the scene loads, so it is
## somewhere new every time the player enters the hub.
##
## Defaults to TRUE. It was previously an opt-in property set per-scene, but
## saving the scene from the Godot editor dropped it (the editor only writes
## properties that differ from the script default), and the door then sat at
## whatever position got baked in. As a default it cannot be lost that way.
@export var random_spawn := true
## Radius around the origin to search, in metres. The hub field is 100x100, so
## 40 keeps the door inside the walls.
@export var spawn_radius := 40.0
## Keep at least this far from the world origin, so it is not on the player.
@export var spawn_min_radius := 12.0
## Try this many times to find a spot that is not inside something.
@export var spawn_attempts := 60
## Anything on these layers counts as "occupied" and is avoided.
@export_flags_3d_physics var blocked_layers := 0xFFFFFFFF

var _inside := false
var _dwell := 0.0
var _fired := false
var _fade: ColorRect


func _ready() -> void:
	# Find the trigger by TYPE, not by a hardcoded name.
	#
	# This used to be get_node_or_null("Area3D"), but the nodes in the hub are
	# named "Trigger". So the lookup returned null, _ready bailed, and NO hub
	# door ever fired. Found while wiring the ACT 1 door.
	var area := _find_area()
	if area == null:
		push_warning("Doorway '%s': no Area3D child, this door will not work." % name)
		return
	area.body_entered.connect(_on_enter)
	area.body_exited.connect(_on_exit)

	# fade overlay
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "DoorFade"
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

	if random_spawn:
		# Deferred: the physics server needs a frame before overlap tests are
		# meaningful, otherwise every spot reads as clear.
		call_deferred("_randomise_position")


## Move the whole doorway to a random clear spot on the field.
##
## Picks a random point in an annulus around the origin, then rejects it if a
## physics body is already there - so the door does not spawn inside a house,
## a tree, or a wall. Falls back to the original position if nothing is found,
## rather than leaving the door somewhere unusable.
func _randomise_position() -> void:
	var start := global_position
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for attempt in spawn_attempts:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(spawn_min_radius, spawn_radius)
		var candidate := Vector3(cos(angle) * dist, start.y, sin(angle) * dist)

		if _is_clear(candidate):
			global_position = candidate
			return

	# nothing clear found - stay put rather than spawn somewhere broken
	push_warning("Doorway '%s': no clear random spot in %d tries, staying at %s"
		% [name, spawn_attempts, start])


## Is this spot free of static bodies and other areas?
##
## NOTE: this uses its own small test box rather than the trigger's own shape.
## The trigger box is tall, and a query placed at the door's origin reaches down
## into the GROUND plane - which made every candidate read as blocked, so the
## door never moved at all.
func _is_clear(pos: Vector3) -> bool:
	var probe := BoxShape3D.new()
	probe.size = Vector3(2.4, 1.8, 2.4)

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	# lifted clear of the floor: ground top sits around y = 0.5
	params.transform = Transform3D(Basis(), Vector3(pos.x, pos.y + 1.6, pos.z))
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = blocked_layers
	params.margin = 0.0

	var hits := get_world_3d().direct_space_state.intersect_shape(params, 1)
	return hits.is_empty()


## The trigger Area3D, found by type. Falls back to the old hardcoded name so
## scenes built against the previous behaviour keep working.
func _find_area() -> Area3D:
	for c in get_children():
		if c is Area3D:
			return c as Area3D
	var legacy := get_node_or_null("Area3D")
	if legacy is Area3D:
		return legacy as Area3D
	return null


func _on_enter(body: Node3D) -> void:
	if body is CharacterBody3D:
		_inside = true
		_dwell = 0.0


func _on_exit(body: Node3D) -> void:
	if body is CharacterBody3D:
		_inside = false
		_dwell = 0.0


func _process(delta: float) -> void:
	if not enabled or _fired or not _inside:
		return
	_dwell += delta
	if _dwell >= dwell_seconds:
		_fired = true
		_go()


## Where this door leads. `next_act` (an id from GameState.ACTS) wins over the
## raw path, so the hub does not need to know scene paths.
func resolve_target() -> String:
	if next_act != "":
		var p: String = GameState.scene_for_act_id(next_act)
		if p != "":
			return p
		push_warning("Doorway '%s': unknown act '%s'" % [name, next_act])
	if target_scene != "":
		return target_scene
	return ""


func _go() -> void:
	var path := resolve_target()
	if path == "":
		push_warning("Doorway '%s': no destination set." % name)
		_fired = true
		return

	# fade to black so the cut is not a pop
	if _fade != null:
		var t := 0.0
		while t < fade_seconds:
			t += get_process_delta_time()
			_fade.color.a = clampf(t / maxf(fade_seconds, 0.01), 0.0, 1.0)
			await get_tree().process_frame

	if next_act != "":
		GameState.current_act = next_act
	GameState.set_gameplay_mouse(true)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Doorway: failed to load '%s' (error %d)" % [path, err])
		_fired = false
		if _fade != null:
			_fade.color.a = 0.0
