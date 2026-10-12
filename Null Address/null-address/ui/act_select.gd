extends Control

## ACT SELECT - reach any act directly.
##
## Opened from the main menu (ACTS) or with the `act_select` input action.
## Builds itself from GameState.ACTS, so adding an act to that registry is all
## it takes for it to appear here.
##
## Each row shows the act number, title, venue and a one-line description. Acts
## that are not `available` are shown greyed and unclickable rather than hidden,
## so the player can see the run's shape.

## Row height. Three text lines (title 34, objective 26, venue 19) plus the
## container separation and the button's own padding need ~100px; 78 clipped the
## venue line.
const ROW_H := 104

const UIStyle := preload("res://ui/ui_style.gd")

var _list: VBoxContainer
var _hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Music.play_menu()
	_build()
	GameState.set_gameplay_mouse(false)


func _build() -> void:
	# dim behind the panel
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(UIStyle.make_label("SELECT ACT", 64, UIStyle.COL_TEXT_BRIGHT))
	var done_n := GameState.completed_acts.size()
	col.add_child(UIStyle.make_label(
		"%d / %d completed" % [done_n, GameState.ACTS.size()],
		22, UIStyle.COL_TEXT_DIM))

	var sub := UIStyle.make_label(
		"Each act is a place to film. pick one to jump straight in.",
		24, UIStyle.COL_TEXT_DIM)
	col.add_child(sub)

	var rule := ColorRect.new()
	rule.color = Color(UIStyle.COL_TEXT_DIM.r, UIStyle.COL_TEXT_DIM.g,
		UIStyle.COL_TEXT_DIM.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	# The list lives in a ScrollContainer that TAKES ALL the leftover height
	# (SIZE_EXPAND_FILL), and the back button is added to `col` AFTER it, so the
	# button is pinned below the list and never scrolls out of reach. Without the
	# scroll container a fifth act pushed the back button off the bottom of the
	# screen with no way to reach it.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var hint := UIStyle.make_label("ESC  /  click here to go back", 22, UIStyle.COL_TEXT_DIM)
	# The label alone is not clickable, so wrap it in a button. This used to
	# pass `_hint`, which is never assigned (it is null), so button_of() read a
	# meta off null, threw, and aborted _build() before _populate() ran - which
	# is why the screen showed no rows at all.
	var back := Button.new()
	back.flat = false
	back.focus_mode = Control.FOCUS_ALL
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.custom_minimum_size = Vector2(0, 50)
	back.add_child(hint)
	back.pressed.connect(_back)
	col.add_child(back)

	_populate()


func _populate() -> void:
	for i in GameState.ACTS.size():
		var a: Dictionary = GameState.ACTS[i]
		_list.add_child(_make_row(a, i))

	var first := _first_button()
	if first != null:
		first.grab_focus()


func _make_row(a: Dictionary, index: int) -> Control:
	var id: String = a.get("id", "")
	var built: bool = GameState.is_act_built(id)
	var unlocked: bool = GameState.is_act_unlocked(id)
	var done: bool = GameState.is_act_completed(id)
	var playable := built and unlocked

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, ROW_H)
	btn.focus_mode = Control.FOCUS_ALL if playable else Control.FOCUS_NONE
	btn.disabled = not playable
	btn.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if playable else Control.CURSOR_ARROW)
	# tag the row so _first_button() can focus the act the player is actually in
	btn.set_meta("act", a)

	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 2)
	btn.add_child(inner)

	# --- title line: locked acts read as "???" so nothing is spoiled ---
	var head: String
	var head_col: Color
	if not built:
		head = "ACT %d  -  COMING SOON" % [a.get("act", index + 1)]
		head_col = UIStyle.COL_TEXT_DIM
	elif not unlocked:
		head = "ACT %d  -  LOCKED" % [a.get("act", index + 1)]
		head_col = UIStyle.COL_TEXT_DIM
	else:
		head = "ACT %d  -  %s" % [a.get("act", index + 1), a.get("title", "?")]
		head_col = UIStyle.COL_TEXT_BRIGHT
	inner.add_child(UIStyle.make_label(head, 34, head_col))

	# --- second line: the OBJECTIVE, which is what the act is actually about ---
	var line: String
	var line_col: Color = UIStyle.COL_REC
	if not built:
		line = "not built yet"
		line_col = UIStyle.COL_TEXT_DIM
	elif not unlocked:
		line = "finish the act before this one to unlock"
		line_col = UIStyle.COL_TEXT_DIM
	else:
		line = str(a.get("objective", "GET OUT"))
	inner.add_child(UIStyle.make_label(line, 26, line_col))

	# --- third line: where it is, and a note on what to expect ---
	var where: String = str(a.get("venue", id)).to_upper()
	var note: String = str(a.get("blurb", ""))
	if note != "":
		where += "   -   " + note
	inner.add_child(UIStyle.make_label(where, 19, UIStyle.COL_TEXT_DIM))

	if playable:
		btn.pressed.connect(_on_pick.bind(a))

	# --- badges: done / current ---
	if done:
		inner.add_child(UIStyle.make_label("COMPLETED", 18, UIStyle.COL_DONE))
	elif id == GameState.current_act and playable:
		inner.add_child(UIStyle.make_label("CURRENT", 18, UIStyle.COL_REC))

	return btn


func _first_button() -> Button:
	# Focus the act the player is currently in, or the first playable one.
	# The hub is always playable, so "first playable" would always be ACT 0 even
	# when the player is mid-run in act 3.
	var target: Control = null
	for c in _list.get_children():
		if not (c is Button) or (c as Button).disabled:
			continue
		if target == null:
			target = c
		var a: Dictionary = c.get_meta("act", {})
		if str(a.get("id", "")) == GameState.current_act:
			target = c
			break
	if target != null:
		return target as Button
	# every act locked (should not happen - the hub is always open) - fall back
	# to the back button so keyboard users are never stuck
	for c in get_children():
		var b := _find_back(c)
		if b != null:
			return b
	return null


func _find_back(n: Node) -> Button:
	if n is Button and n.pressed.get_connections().size() > 0:
		return n as Button
	for c in n.get_children():
		var f := _find_back(c)
		if f != null:
			return f
	return null


func _on_pick(a: Dictionary) -> void:
	var id: String = a.get("id", "")
	if id == "":
		return
	GameState.current_act = id
	GameState.set_gameplay_mouse(true)
	get_tree().change_scene_to_file(a["scene"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	GameState.set_gameplay_mouse(false)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
