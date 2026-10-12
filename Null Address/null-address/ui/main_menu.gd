extends Control

## Main menu — the 2D front end that runs before the 3D level-select hub.
##
## Framed as a camcorder viewfinder: REC indicator, running timecode, date
## stamp, battery, and framing brackets, over a CRT/VHS background plate.

const SETTINGS_PANEL := preload("res://ui/settings_panel.gd")
const UIStyle := preload("res://ui/ui_style.gd")

const MENU_ITEMS := [
	{"label": "START", "action": "start"},
	{"label": "ACTS", "action": "acts"},
	{"label": "SETTINGS", "action": "settings"},
	{"label": "CREDIT" , "action": "credit"},
	{"label": "QUIT", "action": "quit"},
]

# Deliberately has NO "level" entry: the hub is not selectable from the front
# end, so a stale index can never send START to the wrong map.
const HUB_SCENE := "res://Maps/HUBsc.tscn"

# Fake tape start so the timecode reads like a tape that has been running.
const TIMECODE_START := 11 * 3600 + 42 * 60 + 7  # 11:42:07

@onready var _menu_box: VBoxContainer = %MenuBox
@onready var _timecode: Label = %Timecode
@onready var _status: Label = %Status

var _rec_dot: Label
var _rec_timer := 0.0
var _rec_on := true
var _tc_offset := 0.0
var _settings_open := false


func _ready() -> void:
	GameState.set_gameplay_mouse(false)
	Music.play("menu")

	_build_menu()
	_build_rec_indicator()
	_build_framing()

	_tc_offset = float(TIMECODE_START)

	var first := UIStyle.button_of(_menu_box.get_child(0) as HBoxContainer)
	first.grab_focus()


func _process(delta: float) -> void:
	_tc_offset += delta

	# Blinking REC dot, ~1 blink/sec
	_rec_timer += delta
	if _rec_timer >= 0.55:
		_rec_timer = 0.0
		_rec_on = not _rec_on
		_rec_dot.modulate.a = 1.0 if _rec_on else 0.12

	_timecode.text = _format_timecode(_tc_offset)


func _unhandled_input(event: InputEvent) -> void:
	if _settings_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_quit()


# --- build ---

func _build_menu() -> void:
	for item in MENU_ITEMS:
		var row := UIStyle.make_menu_item(item["label"])
		var b := UIStyle.button_of(row)
		b.pressed.connect(_on_menu_action.bind(item["action"]))
		_menu_box.add_child(row)


func _build_rec_indicator() -> void:
	var hbox := %RecRow as HBoxContainer

	_rec_dot = UIStyle.make_label("●", UIStyle.SIZE_OSD, UIStyle.COL_REC)
	hbox.add_child(_rec_dot)

	var rec_label := UIStyle.make_label("REC", UIStyle.SIZE_OSD, UIStyle.COL_TEXT)
	hbox.add_child(rec_label)


## Corner framing brackets, drawn as four thin L-shaped ColorRects.
func _build_framing() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)

	var m := 46.0    # margin from screen edge
	var arm := 42.0  # length of each bracket arm
	var t := 2.0     # thickness
	var c := Color(1, 1, 1, 0.30)

	var corners := [
		Vector2(m, m), Vector2(-m, m), Vector2(m, -m), Vector2(-m, -m),
	]
	for i in corners.size():
		var pos: Vector2 = corners[i]
		var right: bool = pos.x < 0.0
		var down: bool = pos.y < 0.0

		var h := ColorRect.new()
		h.color = c
		h.size = Vector2(arm, t)
		h.position = Vector2(pos.x - (arm if right else 0.0), pos.y)
		h.anchor_left = 0.0 if not right else 1.0
		h.anchor_right = 0.0 if not right else 1.0
		h.anchor_top = 0.0 if not down else 1.0
		h.anchor_bottom = 0.0 if not down else 1.0
		h.offset_left = pos.x - (arm if right else 0.0)
		h.offset_right = pos.x if right else pos.x + arm
		h.offset_top = pos.y
		h.offset_bottom = pos.y + t
		layer.add_child(h)

		var v := ColorRect.new()
		v.color = c
		v.size = Vector2(t, arm)
		v.anchor_left = 0.0 if not right else 1.0
		v.anchor_right = 0.0 if not right else 1.0
		v.anchor_top = 0.0 if not down else 1.0
		v.anchor_bottom = 0.0 if not down else 1.0
		v.offset_left = pos.x - (t if right else 0.0)
		v.offset_right = pos.x if right else pos.x + t
		v.offset_top = pos.y - (arm if down else 0.0)
		v.offset_bottom = pos.y if down else pos.y + arm
		layer.add_child(v)


# --- actions ---

func _on_menu_action(action: String) -> void:
	match action:
		"start":
			# Go straight to the hub. Do not route this through
			# GameState.selected_level — a stale index there could point at a
			# level that is not built yet and START would silently do nothing.
			var err := get_tree().change_scene_to_file(HUB_SCENE)
			if err != OK:
				push_error("Failed to load hub scene '%s' (error %d)" % [HUB_SCENE, err])
			else:
				GameState.set_gameplay_mouse(true)
		"acts":
			_open_acts()
		"credit":
			_open_credits()
		"settings":
			_open_settings()
		"quit":
			_on_quit()

func _open_credits() -> void:
	GameState.set_gameplay_mouse(false)
	get_tree().change_scene_to_file("res://ui/credits.tscn")


func _open_acts() -> void:
	GameState.set_gameplay_mouse(false)
	get_tree().change_scene_to_file("res://ui/act_select.tscn")


func _on_quit() -> void:
	GameState.commit_settings()
	get_tree().quit()


func _open_settings() -> void:
	if _settings_open:
		return
	_settings_open = true

	var panel: Control = SETTINGS_PANEL.new()
	panel.closed.connect(func() -> void:
		_settings_open = false
		var first := UIStyle.button_of(_menu_box.get_child(0) as HBoxContainer)
		first.grab_focus()
	)
	add_child(panel)
	panel.call_deferred("focus_first")


func _format_timecode(seconds_total: float) -> String:
	var s := int(seconds_total)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	return "%02d:%02d:%02d" % [h, m, sec]
