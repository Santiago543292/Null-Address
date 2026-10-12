extends Node

## HIDING SPOTS - the registry that makes hiding actually work.
##
## Every hiding volume in the hub registers here. The watcher asks this node
## `is_hidden()` before it makes a cue, so a player who is inside a wardrobe is
## genuinely not found.
##
## THE POINT OF A REGISTRY rather than each spot checking itself: the watcher
## needs ONE answer to "is the player hidden right now", and it must be the same
## answer regardless of how many spots exist. Scattering the check across the
## spots means the watcher has to know about all of them, and any spot that
## forgets to report leaves hiding silently broken.
##
## Hiding requires DWELL, not just contact. Ducking in for a frame should not
## work - the player has to commit, which is what makes it tense.

@export_group("Hiding")
## Default seconds the player must stay in a spot before they count as hidden.
@export var default_dwell := 1.2
## If the player moves faster than this while in a spot, they are not hidden.
## Stops "run through the wardrobe" from being a free escape.
@export var max_hide_speed := 1.2
## Show a quiet on-screen cue while hidden, so the player knows it worked.
@export var show_hidden_cue := true

signal hidden_changed(hidden: bool)

var _spots: Array[Area3D] = []
var _dwell: Dictionary = {}       # area -> seconds required
var _progress: Dictionary = {}    # area -> seconds accumulated
var _player: CharacterBody3D
var _hidden := false
var _in_any := false
var _label: Label


func _ready() -> void:
	_player = _body(get_parent())
	_discover_spots()
	_build_cue()


## Auto-discover hiding volumes in the scene.
##
## The hub's house_interior.gd calls register() for each volume it builds.
## Generated acts have no such script, so the registry must find them itself.
## It looks for Area3D nodes under a "HidingSpotsGeo" parent (or any Area3D
## with collision_mask == 1 that isn't the player).
func _discover_spots() -> void:
	# Walk up to the scene root (the act or hub), not get_tree().current_scene,
	# because the scene may be instantiated as a child of root in tests.
	var root: Node = self
	while root.get_parent() != null and root.get_parent() != get_tree().root:
		root = root.get_parent()
	# try the named parent first
	var geo := root.get_node_or_null("HidingSpotsGeo")
	if geo != null:
		for c in geo.get_children():
			if c is Area3D and not _spots.has(c):
				register(c)
	# also check for any Area3D with collision_mask == 1 that isn't the player
	for c in root.get_children():
		if c is Area3D and c.collision_mask == 1 and not _spots.has(c):
			register(c)


## Called by each house interior as it builds its hiding volume.
func register(area: Area3D, dwell: float = -1.0) -> void:
	if area == null or _spots.has(area):
		return
	_spots.append(area)
	_dwell[area] = dwell if dwell > 0.0 else default_dwell
	area.body_entered.connect(_on_enter.bind(area))
	area.body_exited.connect(_on_exit.bind(area))


func _on_enter(body: Node3D, area: Area3D) -> void:
	if body is CharacterBody3D:
		_in_any = true
		# start this spot's progress from zero
		_progress[area] = 0.0


func _on_exit(body: Node3D, area: Area3D) -> void:
	if not (body is CharacterBody3D):
		return
	_progress[area] = 0.0
	# only leave "in a spot" when we are out of EVERY spot
	# Filter to CharacterBody3D only - otherwise the house's own StaticBody3D
	# counts as an overlap and the hiding state never clears.
	var still := false
	for s in _spots:
		if not is_instance_valid(s):
			continue
		for b in s.get_overlapping_bodies():
			if b is CharacterBody3D:
				still = true
				break
		if still:
			break
	if not still:
		_in_any = false
		_set_hidden(false)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _body(get_parent())
		if _player == null:
			return

	if not _in_any:
		return

	# Are we actually inside one of the volumes right now?
	var inside: Area3D = null
	for s in _spots:
		if not is_instance_valid(s):
			continue
		if s.get_overlapping_bodies().has(_player):
			inside = s
			break
	if inside == null:
		_in_any = false
		_set_hidden(false)
		return

	# standing still matters - sprinting through a wardrobe is not hiding
	var moving := _player.velocity.length() > max_hide_speed
	if moving:
		_accumulate(inside, -delta * 2.0)      # losing it fast if you move
		return
	_accumulate(inside, delta)


func _accumulate(area: Area3D, delta: float) -> void:
	var t := float(_progress.get(area, 0.0)) + delta
	_progress[area] = maxf(0.0, t)
	var need := float(_dwell.get(area, default_dwell))
	if t >= need and not _hidden:
		_set_hidden(true)


## THE ANSWER THE WATCHER ASKS. True means: do not find the player.
func is_hidden() -> bool:
	return _hidden


## How many spots are registered, for tests.
func spot_count() -> int:
	return _spots.size()


func _set_hidden(v: bool) -> void:
	if v == _hidden:
		return
	_hidden = v
	if v:
		# reset progress so leaving and re-entering needs the full dwell again
		for k in _progress.keys():
			_progress[k] = 0.0
	if _label != null:
		_label.text = "HIDDEN" if v else ""
	hidden_changed.emit(v)


func _build_cue() -> void:
	if not show_hidden_cue:
		return
	var layer := CanvasLayer.new()
	layer.name = "HideCue"
	layer.layer = 62
	add_child(layer)
	_label = Label.new()
	_label.text = ""
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -140.0
	_label.offset_right = 140.0
	_label.offset_top = -196.0
	_label.offset_bottom = -156.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.7, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 7)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)


func _body(n: Node) -> CharacterBody3D:
	if n == null:
		return null
	if n is CharacterBody3D:
		return n
	for c in n.get_children():
		var f := _body(c)
		if f != null:
			return f
	return null
