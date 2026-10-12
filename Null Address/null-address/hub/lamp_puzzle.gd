extends Node

## The lamp puzzle - find the odd one out.
##
## Every lamp looks identical: warm white, steady. One of them, chosen at
## random each attempt, flashes RED now and then. The player walks the field,
## watches, and presses E on the lamp they think is the odd one.
##
## Three wrong picks and they pass out: the screen goes black, they wake at the
## start, and a fresh lamp is chosen. This is the "something is out there" beat
## before the monster is ever shown - the passing out is the only evidence.
##
## Attach to a plain Node in the hub scene. It adopts every Lamp_N under
## LampPosts, so adding a lamp to the scene adds it to the puzzle.

@export_group("Puzzle")
## How many wrong picks before the player passes out.
@export var max_wrong := 3
## Seconds between red tells.
@export var tell_min_gap := 2.6
@export var tell_max_gap := 6.5
## Seconds after the player first looks at the field before the tells start,
## so they get a moment to notice the lamps are all normal first.
@export var grace_seconds := 3.0

@export_group("Passing Out")
## How long the blackout lasts.
@export var faint_seconds := 2.6
## Fade to black time, each way.
@export var fade_seconds := 0.9
## Where the player wakes up. Empty means the scene's spawn point.
@export var wake_position := Vector3.ZERO
@export var use_scene_spawn := true

@export_group("Blackout Escalation")
## Each blackout makes the next one worse. `blackouts` counts how many times the
## player has passed out; every effect below scales with it.
@export var escalate_blackouts := true
## Extra seconds of blackout per previous blackout.
@export var faint_growth := 1.1
## Extra seconds of fade per previous blackout.
@export var fade_growth := 0.25
## Seconds of silence before the music comes back, per blackout.
@export var silence_growth := 2.0
## How far the tells slow down per blackout - the odd lamp hides better.
@export var tell_gap_growth := 1.35
## At this many blackouts the whole screen starts to glitch on waking.
@export var glitch_after := 2

@export_group("Door Gate")
## The ACT door only becomes usable once the puzzle is solved.
@export var door_name := "ActDoor_1"
## Keep the door buried until the puzzle is solved.
@export var gate_the_door := true

signal solved()
signal wrong_pick(remaining: int)
signal passed_out()

var _lamps: Array[Node3D] = []
var _the_one: Node3D
var _wrong := 0
var _solved := false
var _t := 0.0
var _next_tell := 0.0
var _blackout: ColorRect
var _spawn := Vector3.ZERO
var _busy := false
var _rng := RandomNumberGenerator.new()
var blackouts := 0
var _wake_glitch: ColorRect
var _near: Array[Node3D] = []
var _hud: CanvasLayer
var _prompt: Label
var _counter: Label
var _flash: ColorRect


func _ready() -> void:
	_rng.randomize()
	_collect_lamps()
	_build_hud()
	_build_blackout()
	_build_wake_glitch()
	_find_spawn()
	if gate_the_door:
		_bury_door()
	_choose_the_one()
	_next_tell = grace_seconds


func _collect_lamps() -> void:
	var holder := get_parent().get_node_or_null("LampPosts")
	if holder == null:
		push_warning("LampPuzzle: no LampPosts node")
		return
	for c in holder.get_children():
		if c is Node3D and c.name.begins_with("Lamp_"):
			_lamps.append(c as Node3D)
	print("LampPuzzle: %d lamps" % _lamps.size())


## Pick a fresh odd-one-out. Never the same lamp twice in a row.
func _choose_the_one() -> void:
	if _lamps.is_empty():
		return
	var prev := _the_one
	for attempt in 20:
		var pick: Node3D = _lamps[_rng.randi_range(0, _lamps.size() - 1)]
		if pick != prev or _lamps.size() == 1:
			_the_one = pick
			break
	if _the_one != null and _the_one.has_method("make_the_one"):
		_the_one.call("make_the_one")


func _process(delta: float) -> void:
	if _solved or _busy or _lamps.is_empty():
		return
	_t += delta
	if _t < _next_tell:
		return
	_next_tell = _t + _rng.randf_range(tell_min_gap, tell_max_gap)
	if _the_one != null and _the_one.has_method("flash_tell"):
		_the_one.call("flash_tell")


## The player pressed E on a lamp.
func pick_lamp(lamp: Node3D) -> void:
	if _solved or _busy:
		return
	if lamp == _the_one:
		_solved = true
		_update_prompt()
		solved.emit()
		_on_solved()
		return

	_wrong += 1
	var remaining := max_wrong - _wrong
	_flash_reject()
	_update_counter()
	wrong_pick.emit(remaining)
	if remaining <= 0:
		_pass_out()


func _on_solved() -> void:
	# the odd lamp stays lit red so the player can see they got it
	if _the_one != null and _the_one.has_method("hold_tell"):
		_the_one.call("hold_tell")
	if gate_the_door:
		_release_door()


## Push the hub's corruption up a step, permanently, for this blackout.
##
## Finds the escalation and the map glitch by CAPABILITY rather than by name, so
## this keeps working if either is renamed. Each blackout adds a step to the
## escalation's floor: the world does not reset to calm when the player wakes, it
## resets to slightly worse than before.
func _escalate_world_corruption() -> void:
	for c in get_parent().get_children():
		# the escalation exposes boost(); the map glitch exposes set_baseline()
		if c.has_method("boost"):
			c.call("boost", 0.18)
		elif c.has_method("set_baseline"):
			c.call("set_baseline", 0.12 * float(blackouts))


## Black out, then wake at the start with a new odd lamp.
func _pass_out() -> void:
	_busy = true
	blackouts += 1
	passed_out.emit()

	# Every blackout makes the whole hub glitchier, not just this puzzle. Each
	# blackout pushes the corruption escalation's baseline up permanently, so the
	# world the player wakes into is worse than the one they passed out in.
	_escalate_world_corruption()

	# every blackout is worse: longer fade, longer dark, longer silence
	var fade := fade_seconds + (blackouts - 1) * fade_growth
	var dark := faint_seconds + (blackouts - 1) * faint_growth

	if _blackout != null:
		var t := create_tween()
		t.tween_property(_blackout, "color:a", 1.0, fade)
		await t.finished

	# the music cuts out while they are under, for longer each time
	var silence := silence_growth * float(blackouts)
	Music.stop()

	await get_tree().create_timer(dark).timeout

	# waking up gets rougher the more it happens
	if blackouts >= glitch_after and _wake_glitch != null:
		await _run_wake_glitch()

	# wake up back at the spawn
	var player := _find_player()
	if player != null:
		player.global_position = _spawn
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

	# reset the puzzle with a fresh lamp
	_wrong = 0
	_near.clear()
	_update_prompt()
	_update_counter()
	_the_one = null
	_choose_the_one()
	_t = 0.0
	_next_tell = grace_seconds

	# tells get slower, so the odd lamp is harder to catch
	var gap_scale := pow(tell_gap_growth, float(blackouts - 1))
	tell_min_gap *= gap_scale
	tell_max_gap *= gap_scale

	if _blackout != null:
		var b := create_tween()
		b.tween_property(_blackout, "color:a", 0.0, fade)
		await b.finished

	# music comes back after the silence
	Music.play_ungood()
	await get_tree().create_timer(silence * 0.25).timeout

	_busy = false


## The pop-up: a prompt when a lamp is in reach, a wrong-pick counter, and a
## full-screen flash when a lamp is rejected.
##
## Built in code so no scene edit is needed and it cannot drift from the puzzle.
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "LampHUD"
	_hud.layer = 60
	add_child(_hud)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	# the "press E" prompt, low centre - where a game puts an interact hint
	_prompt = Label.new()
	_prompt.text = ""
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.offset_left = -260.0
	_prompt.offset_right = 260.0
	_prompt.offset_top = -150.0
	_prompt.offset_bottom = -104.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 30)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_prompt)

	# wrong-pick counter, top left
	_counter = Label.new()
	_counter.text = ""
	_counter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_counter.offset_left = 60.0
	_counter.offset_top = 40.0
	_counter.add_theme_font_size_override("font_size", 26)
	_counter.add_theme_color_override("font_color", Color(0.88, 0.20, 0.18, 1))
	_counter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_counter.add_theme_constant_override("outline_size", 6)
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_counter)

	# the rejection flash
	_flash = ColorRect.new()
	_flash.color = Color(0.9, 0.1, 0.1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)


## Show or hide the "press E" prompt.
func _update_prompt() -> void:
	if _prompt == null:
		return
	if _solved or _busy or _near.is_empty():
		_prompt.text = ""
		return
	_prompt.text = "[E]  FIND A LAMP"


func _update_counter() -> void:
	if _counter == null:
		return
	if _wrong <= 0 or _solved:
		_counter.text = ""
	else:
		_counter.text = "WRONG  %d / %d" % [_wrong, max_wrong]


## Flash the screen red when a lamp is rejected.
func _flash_reject() -> void:
	if _flash == null:
		return
	_flash.color = Color(0.9, 0.1, 0.1, 0.28)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.45)


func lamp_entered_range(lamp: Node3D) -> void:
	if not _near.has(lamp):
		_near.append(lamp)
	_update_prompt()


func lamp_left_range(lamp: Node3D) -> void:
	_near.erase(lamp)
	_update_prompt()


## The nearest lamp in reach, or null.
func _nearest_in_reach() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var player := _find_player()
	if player == null:
		return _near[0] if not _near.is_empty() else null
	for l in _near:
		if not is_instance_valid(l):
			continue
		var d := l.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = l
	return best


## The manager owns the key, not the 12 lamps. One handler, one prompt.
func _unhandled_input(event: InputEvent) -> void:
	if _solved or _busy:
		return
	if not event.is_action_pressed("interact"):
		return
	var target := _nearest_in_reach()
	if target == null:
		return
	get_viewport().set_input_as_handled()
	pick_lamp(target)


## A screen-tearing flash on waking, worse with each blackout.
func _run_wake_glitch() -> void:
	var layers := 3 + blackouts
	for i in layers:
		_wake_glitch.color = Color(
			_rng.randf_range(0.4, 1.0),
			_rng.randf_range(0.0, 0.3),
			_rng.randf_range(0.5, 1.0),
			_rng.randf_range(0.10, 0.30))
		_wake_glitch.visible = true
		await get_tree().create_timer(0.05 + _rng.randf() * 0.12).timeout
		_wake_glitch.visible = false
		await get_tree().create_timer(0.03).timeout


func _build_wake_glitch() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 118
	layer.name = "WakeGlitchLayer"
	add_child(layer)
	_wake_glitch = ColorRect.new()
	_wake_glitch.color = Color(0.6, 0.1, 0.7, 0.0)
	_wake_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wake_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wake_glitch.visible = false
	layer.add_child(_wake_glitch)


func _build_blackout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.name = "FaintLayer"
	add_child(layer)

	_blackout = ColorRect.new()
	_blackout.color = Color(0, 0, 0, 0)
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_blackout)


func _find_spawn() -> void:
	var player := _find_player()
	if player != null:
		_spawn = player.global_position


func _find_player() -> Node3D:
	var root := get_tree().current_scene
	if root == null:
		return null
	return _find_body(root)


func _find_body(n: Node) -> Node3D:
	if n is CharacterBody3D:
		return n as Node3D
	for c in n.get_children():
		var f := _find_body(c)
		if f != null:
			return f
	return null


## Hold the ACT door down until the puzzle is solved.
func _bury_door() -> void:
	var door := get_parent().get_node_or_null(door_name)
	if door == null:
		return
	if "rise_on_trigger" in door:
		door.set("rise_on_trigger", false)


func _release_door() -> void:
	var door := get_parent().get_node_or_null(door_name)
	if door == null:
		return
	if "rise_on_trigger" in door:
		door.set("rise_on_trigger", true)
	# and rise it now, since the player has earned it
	if door.has_method("rise"):
		door.call("rise")


func wrong_count() -> int:
	return _wrong


func is_solved() -> bool:
	return _solved


func lamp_count() -> int:
	return _lamps.size()


## Which lamp is currently the odd one. For tests.
func the_one() -> Node3D:
	return _the_one
