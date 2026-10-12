extends Node

## Whole-map glitch, driven by the escalation.
##
## When the door rises, everything EXCEPT the ground starts corrupting: props
## jitter and blink, trees sway wrong, and the buildings outside the map flicker
## their lights. The floor is deliberately left alone - a glitching floor reads
## as a broken game, a glitching world reads as wrong.
##
## This is the counterpart to the door being hidden: door hidden = everything
## normal; door open = everything wrong.
##
## Attach to a plain Node in the hub.

@export_group("Targets")
## Node groups to corrupt. The ground is excluded by name, not by group, so
## anything the level designer drops into the scene is picked up automatically.
@export var exclude_names := ["Ground", "Ground2", "Boundary", "Skyline"]
## Corrupt anything further than this from the door, in metres.
@export var min_distance_from_door := 6.0

@export_group("Behaviour")
## Only start once the door is up.
@export var wait_for_door := true
## Node name of the door.
@export var door_name := "ActDoor_1"
## Skip the interior props - the zone already handles those.
@export var skip_near_door := true

signal started()

var _targets: Array[Node3D] = []
var _home: Dictionary = {}
var _running := false
var _t := 0.0
var _accum := 0.0
var _blink_left := 0.0
var _rng := RandomNumberGenerator.new()
var _door: Node3D
var _esc: Node


func _ready() -> void:
	_rng.randomize()
	_door = get_parent().get_node_or_null(door_name) as Node3D
	# the escalation owns the master ramp; read it rather than keeping a second
	# clock that will drift out of step
	for c in get_parent().get_children():
		if c.has_method("progress") and c.has_method("peak_db"):
			_esc = c
			break
	if wait_for_door and _door != null and _door.has_signal("risen"):
		_door.connect("risen", _on_risen)
	elif not wait_for_door:
		_running = true


func _on_risen() -> void:
	_collect()
	_running = true
	started.emit()


## Everything worth corrupting: props, trees, houses, the skyline.
func _collect() -> void:
	var root := get_parent()
	var dp := _door.global_position if _door != null else Vector3.ZERO
	for c in root.get_children():
		if not (c is Node3D):
			continue
		if c.name in exclude_names:
			continue
		# recurse one level so grouped props (Houses/House_3) are caught
		for n in _walk(c):
			if not (n is Node3D):
				continue
			var n3 := n as Node3D
			if n3 == _door or _door != null and _door.is_ancestor_of(n3):
				continue
			if skip_near_door and n3.global_position.distance_to(dp) < min_distance_from_door:
				continue
			_targets.append(n3)
			_home[n3] = n3.position
	print("MapGlitch: %d targets" % _targets.size())


func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _process(delta: float) -> void:
	if not _running or _targets.is_empty():
		return

	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			for t in _targets:
				if is_instance_valid(t):
					t.visible = true

	# get worse over time, capped so it never becomes unplayable
	_t += delta
	# drive off the escalation's ramp when one exists, so the world falling apart
	# and the music swelling are the same event rather than two clocks that drift
	var t := _escalation_t()
	var interval := lerpf(0.40, 0.02, t)

	_accum += delta
	if _accum < interval:
		return
	_accum = 0.0
	_corrupt(t)


## The escalation's progress, or our own fallback ramp if there is none.
func _escalation_t() -> float:
	if _esc != null and is_instance_valid(_esc):
		var raw: Variant = _esc.call("progress")
		if raw != null:
			return clampf(float(raw), 0.0, 1.0)
	return clampf(_t / 16.0, 0.0, 1.0)


func _corrupt(t: float) -> void:
	var jitter := lerpf(0.08, 1.10, t)
	var blink := lerpf(0.15, 0.80, t)
	var n := 1 + _rng.randi_range(0, int(lerpf(1.0, 5.0, t)))
	for i in n:
		var target: Node3D = _targets[_rng.randi_range(0, _targets.size() - 1)]
		if not is_instance_valid(target):
			continue
		var home: Vector3 = _home.get(target, target.position)
		if _rng.randf() < blink:
			target.visible = false
			_blink_left = 0.05
		else:
			target.position = home + Vector3(
				_rng.randf_range(-jitter, jitter),
				_rng.randf_range(-jitter * 0.25, jitter * 0.25),
				_rng.randf_range(-jitter, jitter))
		var back := create_tween()
		back.tween_interval(0.3)
		back.tween_callback(func() -> void:
			if is_instance_valid(target):
				target.position = home)


func is_running() -> bool:
	return _running


func target_count() -> int:
	return _targets.size()
