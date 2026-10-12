extends CanvasLayer

## In-game pause menu. Added at runtime by the level scene (or an autoload) so
## the 3D hub does not need a pre-authored overlay node.
##
## Press Esc to open. While open the tree is paused and the mouse is released.

const SETTINGS_PANEL := preload("res://ui/settings_panel.gd")
const UIStyle := preload("res://ui/ui_style.gd")

var _open := false
var _root: Control
var _menu_box: VBoxContainer
var _settings_panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.78)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)

	v.add_child(UIStyle.make_label("PAUSED", UIStyle.SIZE_TITLE, UIStyle.COL_TEXT_BRIGHT))

	var rule := ColorRect.new()
	rule.color = UIStyle.COL_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 4)
	v.add_child(_menu_box)

	_add_item("RESUME", _close)
	_add_item("SETTINGS", _open_settings)
	_add_item("QUIT TO MENU", _quit_to_menu)


func _add_item(label: String, handler: Callable) -> void:
	var row := UIStyle.make_menu_item(label)
	UIStyle.button_of(row).pressed.connect(handler)
	_menu_box.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings_panel != null:
			return  # the settings panel handles its own Esc
		if _open:
			_close()
		else:
			_open_menu()


func _open_menu() -> void:
	_open = true
	_root.visible = true
	get_tree().paused = true
	GameState.set_gameplay_mouse(false)
	var first := UIStyle.button_of(_menu_box.get_child(0) as HBoxContainer)
	first.grab_focus()


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	GameState.set_gameplay_mouse(true)


func _open_settings() -> void:
	if _settings_panel != null:
		return
	_settings_panel = SETTINGS_PANEL.new()
	_settings_panel.closed.connect(func() -> void:
		_settings_panel = null
		var first := UIStyle.button_of(_menu_box.get_child(0) as HBoxContainer)
		first.grab_focus()
	)
	_root.add_child(_settings_panel)
	_settings_panel.call_deferred("focus_first")


func _quit_to_menu() -> void:
	get_tree().paused = false
	GameState.set_gameplay_mouse(false)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
