extends Area3D

## ACT gate — walk through it to move to the next ACT.
##
## Attach this to an Area3D with a CollisionShape3D. When the player's body
## enters, it fades out, loads the target ACT, and fades back in.
##
## The target is set two ways:
##   * `next_act`  — an act id from GameState.ACTS (preferred)
##   * `target_scene` — an explicit res:// path, used if next_act is empty
##
## Set `one_way = true` for gates the player should not be able to walk back
## through (the classic "the door shut behind you" beat).

@export_group("Destination")
## Act id to load: "store", "office", "house", "tunnel".
@export var next_act := ""
## Explicit scene path. Only used when next_act is empty.
@export var target_scene := ""
## Carry the player's filming progress into the next act instead of resetting.
@export var carry_progress := true
## Once used, this gate cannot be re-entered.
@export var one_way := false

@export_group("Dressing")
## Text shown on the sign above the gate, if a RichText3D child exists.
@export var gate_label := ""
## How long the fade takes, each way.
@export var fade_seconds := 0.7
## Seconds the player must stand in the gate before it triggers, so it does
## not fire when they brush past it.
@export var dwell_seconds := 0.35

var _used := false
var _dwell := 0.0
var _firing := false
var _player_inside := false
var _fade: ColorRect


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# A black full-screen rect for the transition. Sits above the tape overlay.
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "ActFade"
	add_child(layer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

	# Paint the label onto a RichText3D child if one was added.
	if gate_label != "":
		for c in get_children():
			if "text" in c:
				c.set("text", gate_label)
				break


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") and not _is_player(body):
		return
	_player_inside = true
	_dwell = 0.0
	# Demo ending: if this is the last act, stop the player and show the message
	if _is_demo_end():
		_show_demo_end()
		return


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player") and not _is_player(body):
		return
	_player_inside = false
	_dwell = 0.0


func _is_player(body: Node) -> bool:
	# The player is a CharacterBody3D; so is nothing else in these acts.
	return body is CharacterBody3D

## Is this the end of the demo? The store (ACT 1) gate leads to the office,
## but the demo ends here — the player should see a message, not a transition.
func _is_demo_end() -> bool:
	return next_act == "office"

## Show the demo ending: a full-screen message and no transition.
func _show_demo_end() -> void:
	_firing = true
	var layer := CanvasLayer.new()
	layer.layer = 200
	layer.name = "DemoEnd"
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	layer.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "END OF DEMO"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var body := Label.new()
	body.text = "You made it out of the store.\nThe rest of Null Address is coming soon."
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(body)

	var hint := Label.new()
	hint.text = "Thanks for playing."
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	# Stop the player so they walk nowhere.
	var player := get_tree().current_scene
	if player != null:
		for c in player.get_children():
			if c is CharacterBody3D:
				c.set("freeze", true)
				c.set("process_mode", Node.PROCESS_MODE_DISABLED)
				break

	# Fade the message in.
	layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(layer, "modulate:a", 1.0, 1.2)


func _process(delta: float) -> void:
	if _firing or _used and one_way:
		return
	if not _player_inside:
		return

	_dwell += delta
	if _dwell < dwell_seconds:
		return

	var path := _resolve_path()
	if path == "":
		push_warning("ActGate: no destination (next_act='%s' target_scene='%s')"
			% [next_act, target_scene])
		_firing = true
		return

	_firing = true
	_go(path)


func _resolve_path() -> String:
	if next_act != "":
		var p: String = GameState.scene_for_act_id(next_act)
		if p != "":
			return p
	if target_scene != "":
		return target_scene
	return ""


func _go(path: String) -> void:
	if carry_progress:
		GameState.remember_film_progress()

	# fade to black
	var t := 0.0
	while t < fade_seconds:
		t += get_process_delta_time()
		_fade.color.a = clampf(t / fade_seconds, 0.0, 1.0)
		await get_tree().process_frame

	if one_way:
		_used = true

	# Reaching the exit means this act is finished, which unlocks the next one
	# in ACT SELECT.
	var here := GameState.current_act
	if here == "":
		# the generated scenes carry the act title as the HUD subtitle; map it
		for a in GameState.ACTS:
			if str(a.get("scene", "")) == (get_tree().current_scene.scene_file_path if get_tree().current_scene else ""):
				here = str(a.get("id", ""))
				break
	if here != "":
		GameState.complete_act(here)

	GameState.advance_to_act(next_act if next_act != "" else path)
	_fade.color.a = 1.0
