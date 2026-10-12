extends Area3D

## The glitch zone - a patch of corrupted ground around the ACT door.
##
## What it does:
##   1. Corrupts the visuals inside the radius: props jitter, snap in and out of
##      visibility, and shift position, so the area reads as WRONG from a
##      distance and the player wants to walk toward it.
##   2. Fires the door's rise the moment the player crosses into it while
##      looking at the door.
##   3. Keeps corrupting harder while the player is inside.
##
## The zone is a sibling of the door, and the door finds it by name
## ("GlitchZone"), so the two stay decoupled.

@export_group("Zone")
## Radius while the door is still buried - a SMALL patch, so the player can see
## a wrong spot on the ground from far away and know where to head.
@export var radius := 5.0
## Radius once the door is up. The corruption spreads to cover the area.
@export var radius_when_open := 13.0
## Node that holds the things to corrupt. Defaults to the zone's parent.
@export var target_path: NodePath

@export_group("Corruption")
## Corrupt things every N seconds while the player is away.
@export var idle_interval := 0.55
## ...and this much faster while the player is inside.
@export var inside_interval := 0.10
## How far a corrupted prop jumps, in metres.
@export var jitter := 0.22
## Chance a given corruption snaps a prop invisible for a frame.
@export_range(0.0, 1.0) var blink_chance := 0.30
## How long a blink lasts, in seconds.
@export var blink_time := 0.06

@export_group("Reveal")
## Seconds between corruption bursts before the player has noticed the zone.
## Slower and subtler, so it reads as a glint rather than a strobe.
@export var distant_interval := 1.4

var _targets: Array[Node3D] = []
var _home: Dictionary = {}
var _accum := 0.0
var _player_inside := false
var _blink_left := 0.0
var _rng := RandomNumberGenerator.new()
var _noticed := false
var _full_glitch := false
var _shape: CollisionShape3D


## Switch from the subtle light-only glitch to full corruption. Called by the
## door once it has risen.
##
## The zone's own light is DARK until this runs: with the door still buried
## there should be nothing to see, and a glowing patch on the ground gave the
## door's position away before it appeared.
func enable_full_glitch() -> void:
	_full_glitch = true
	_apply_radius(radius_when_open)
	# wake the zone light now that there is something to light.
	# Look it up by NAME from the scene root: the earlier loop only accepted
	# lights that already had a script attached, so if the script had not been
	# applied yet the light stayed dark forever.
	var root := get_parent()
	if root != null:
		var zl := root.get_node_or_null("ZoneGlitch")
		if zl is OmniLight3D:
			(zl as OmniLight3D).visible = true


## Every light under a node.
func _lights(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n is OmniLight3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_lights(c))
	return out

signal player_entered()
signal player_exited()


func _ready() -> void:
	monitoring = true
	_rng.randomize()
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

	# build a sphere matching the radius, unless one is already there
	_shape = _existing_shape()
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.shape = SphereShape3D.new()
		add_child(_shape)
	_apply_radius(radius)

	_collect_targets()


## Everything inside the radius worth corrupting.
##
## The generated acts group props under Props/Clutter/Damage/Fixtures, but the
## hub uses Scatter/LampPosts/Houses instead. Rather than hardcode either
## layout, walk every Node3D in the scene and keep whatever falls inside the
## radius. Cheap (a few hundred nodes) and works on both.
func _collect_targets() -> void:
	var root: Node = get_node_or_null(target_path) if target_path != NodePath() else get_parent()
	if root == null:
		return
	var r2 := (radius_when_open * 1.15) * (radius_when_open * 1.15)
	for c in _walk(root):
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if n == self or is_ancestor_of(n):
			continue
		# skip anything huge or structural - houses and the ground should not
		# jitter, only loose props
		if n.name.begins_with("Ground") or n.name.begins_with("Boundary"):
			continue
		if n.global_position.distance_squared_to(global_position) > r2:
			continue
		_targets.append(n)
		_home[n] = n.position


## Every Node3D under `root`, breadth-first.
func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _existing_shape() -> CollisionShape3D:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			return c as CollisionShape3D
	return null


func _apply_radius(r: float) -> void:
	if _shape == null or not (_shape.shape is SphereShape3D):
		return
	(_shape.shape as SphereShape3D).radius = r


func _on_enter(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_player_inside = true
	player_entered.emit()


func _on_exit(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_player_inside = false
	player_exited.emit()


func _process(delta: float) -> void:
	# restore anything that was blinking
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			for t in _targets:
				if is_instance_valid(t):
					t.visible = true

	# Before the door rises the zone only breathes - the light flickers but
	# nothing in the scene moves. Full corruption starts with the door.
	if not _full_glitch:
		return

	_accum += delta
	var interval := inside_interval if _player_inside else (
		idle_interval if _noticed else distant_interval)
	if _accum < interval:
		return
	_accum = 0.0
	_corrupt()


## One burst of corruption.
func _corrupt() -> void:
	if _targets.is_empty():
		return
	_noticed = true
	var n := 1 + _rng.randi_range(0, 2 if _player_inside else 1)
	for i in n:
		var t: Node3D = _targets[_rng.randi_range(0, _targets.size() - 1)]
		if not is_instance_valid(t):
			continue
		var home: Vector3 = _home.get(t, t.position)
		if _rng.randf() < blink_chance:
			t.visible = false
			_blink_left = blink_time
		else:
			t.position = home + Vector3(
				_rng.randf_range(-jitter, jitter),
				_rng.randf_range(-jitter * 0.3, jitter * 0.3),
				_rng.randf_range(-jitter, jitter))
		# ease it back on the next idle tick
		var back := create_tween()
		back.tween_interval(0.25 if _player_inside else 0.9)
		back.tween_callback(func() -> void:
			if is_instance_valid(t):
				t.position = home)


## Is the player currently inside the zone?
func player_inside() -> bool:
	return _player_inside


## How many things are being corrupted. Handy for tests.
func target_count() -> int:
	return _targets.size()
