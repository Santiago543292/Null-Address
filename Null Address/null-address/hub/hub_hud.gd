extends CanvasLayer

## Hub HUD. On entering the hub it fades a title card in, holds it, fades it
## out, and leaves a small persistent tag in the corner so the player always
## knows where they are. The objective line is where "which door next" lives.

const UIStyle := preload("res://ui/ui_style.gd")

@export var level_name := "LEVEL 0"
@export var level_subtitle := "THE HUB"
@export var objective := "PICK A DOOR"
@export var fade_in_time := 1.2
@export var hold_time := 3.5
@export var fade_out_time := 1.6

var _card: Control
var _corner: Control
var _elapsed := 0.0
var _glitch_objective := false
var _glitch_tick := 0
var _obj_label: Label


## Swap the objective to a corrupted string and start mangling it. Called when
## the door rises - the task stops being "keep filming" and becomes "get out".
func glitch_objective() -> void:
	objective = "FIND A LAMP"
	_glitch_objective = true


## Corrupt a string by swapping in glyphs. Deterministic per seed so it shimmers
## rather than exploding.
func _mangle(text: String, amount: float) -> String:
	const GLYPHS := "▓▒░#@%&*!?/|<>~^"
	var out := ""
	var rng := RandomNumberGenerator.new()
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			out += " "
			continue
		rng.seed = hash(text) + i * 7919 + _glitch_tick
		if rng.randf() < amount:
			out += GLYPHS[rng.randi_range(0, GLYPHS.length() - 1)]
		else:
			out += ch
	return out


func _ready() -> void:
	layer = 5
	Music.play_for_act(level_name, level_subtitle)
	# Remember where the player is, so ACT SELECT can show a CURRENT badge.
	var here := _act_id_from(level_subtitle)
	if here != "":
		GameState.current_act = here
	_build()


## Map a HUD subtitle back to an act id. The generated scenes set the subtitle
## to the act title, e.g. "THE OFFICE FLOOR" -> "office".
func _act_id_from(subtitle: String) -> String:
	for a in GameState.ACTS:
		if str(a.get("title", "")).to_upper() == subtitle.to_upper():
			return str(a.get("id", ""))
	return ""


## Push the carried film progress into the tape overlay, so the footage keeps
## degrading across the run instead of resetting each act.
func _apply_carried_progress() -> void:
	var overlay := _find_filming(get_tree().current_scene)
	if overlay != null and overlay.has_method("set_progress"):
		overlay.set_progress(GameState.film_progress)


func _find_filming(n: Node) -> Node:
	if n == null:
		return null
	if n.has_method("set_progress"):
		return n
	for c in n.get_children():
		var f := _find_filming(c)
		if f != null:
			return f
	return null
	_card.modulate.a = 0.0
	_corner.modulate.a = 0.0


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Centre title card ---
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)

	var name_label := UIStyle.make_label(level_name, 84, UIStyle.COL_TEXT_BRIGHT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_label)

	var sub := UIStyle.make_label(level_subtitle, 28, UIStyle.COL_TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	card.add_child(gap)

	var obj := UIStyle.make_label(objective, 20, UIStyle.COL_REC)
	_obj_label = obj
	obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(obj)

	_card = card

	# --- Persistent corner tag ---
	var corner := VBoxContainer.new()
	corner.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	corner.offset_left = 46.0
	corner.offset_top = -84.0
	corner.offset_bottom = -46.0
	corner.add_theme_constant_override("separation", 0)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(corner)

	corner.add_child(UIStyle.make_label(level_name, UIStyle.SIZE_OSD, UIStyle.COL_TEXT))
	corner.add_child(UIStyle.make_label(level_subtitle, UIStyle.SIZE_SMALL, UIStyle.COL_TEXT_DIM))

	_corner = corner


func _process(delta: float) -> void:
	_elapsed += delta

	# once the door is up the objective line corrupts, harder over time
	if _glitch_objective and _obj_label != null:
		_glitch_tick += 1
		var amount := clampf(0.12 + float(_glitch_tick) * 0.00035, 0.0, 0.55)
		_obj_label.text = _mangle(objective, amount)
		_obj_label.add_theme_color_override("font_color",
			UIStyle.COL_REC.lerp(Color(0.85, 0.85, 1.0), amount))

	# Fade in -> hold -> fade out.
	if _elapsed < fade_in_time:
		_card.modulate.a = _elapsed / fade_in_time
	elif _elapsed < fade_in_time + hold_time:
		_card.modulate.a = 1.0
	elif _elapsed < fade_in_time + hold_time + fade_out_time:
		var t := (_elapsed - fade_in_time - hold_time) / fade_out_time
		_card.modulate.a = 1.0 - t
	else:
		_card.modulate.a = 0.0

	# Corner tag settles in once the card has gone.
	var corner_start := fade_in_time + hold_time
	if _elapsed > corner_start:
		_corner.modulate.a = minf((_elapsed - corner_start) / 1.0, 1.0)
