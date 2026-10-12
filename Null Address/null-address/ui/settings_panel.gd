extends Control

## Settings panel. Usable standalone (Settings scene) or embedded as an overlay
## by the front-end / pause menu. Reads and writes GameState, which persists to
## user://settings.cfg.

signal closed

const SENS_MIN := 0.01
const SENS_MAX := 0.30
const FOV_MIN := 60.0
const FOV_MAX := 110.0
const ROW_WIDTH := 280

const _InputForwarder := preload("res://ui/input_forwarder.gd")
const UIStyle := preload("res://ui/ui_style.gd")

var _first_focus: Control


func _ready() -> void:
	Music.play_menu()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	# Dim whatever is behind the panel (menu art, or the paused 3D scene).
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	v.add_child(UIStyle.make_label("SETTINGS", UIStyle.SIZE_TITLE, UIStyle.COL_TEXT_BRIGHT))

	var rule := ColorRect.new()
	rule.color = UIStyle.COL_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)

	# --- Mouse sensitivity ---
	var sens_slider := HSlider.new()
	sens_slider.min_value = SENS_MIN
	sens_slider.max_value = SENS_MAX
	sens_slider.step = 0.001
	sens_slider.value = GameState.sensitivity
	var sens_value := _make_row(v, "MOUSE SENSITIVITY", sens_slider,
		"%.3f" % GameState.sensitivity)
	sens_slider.value_changed.connect(func(val: float) -> void:
		GameState.sensitivity = val
		sens_value.text = "%.3f" % val
		GameState.commit_settings()
	)
	_first_focus = sens_slider

	# --- Invert Y ---
	var invert_button := _make_toggle()
	invert_button.pressed.connect(func() -> void:
		GameState.mouse_invert_y = not GameState.mouse_invert_y
		_set_toggle(invert_button, GameState.mouse_invert_y)
		GameState.commit_settings()
	)
	_make_row(v, "INVERT Y AXIS", invert_button, "")

	# --- Field of view ---
	var fov_slider := HSlider.new()
	fov_slider.min_value = FOV_MIN
	fov_slider.max_value = FOV_MAX
	fov_slider.step = 1.0
	fov_slider.value = GameState.fov
	var fov_value := _make_row(v, "FIELD OF VIEW", fov_slider, "%d" % int(GameState.fov))
	fov_slider.value_changed.connect(func(val: float) -> void:
		GameState.fov = val
		fov_value.text = "%d" % int(val)
		GameState.commit_settings()
	)

	# --- Master volume ---
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.01
	vol_slider.value = GameState.master_volume
	var vol_value := _make_row(v, "MASTER VOLUME", vol_slider,
		"%d%%" % int(round(GameState.master_volume * 100.0)))
	vol_slider.value_changed.connect(func(val: float) -> void:
		GameState.master_volume = val
		vol_value.text = "%d%%" % int(round(val * 100.0))
		GameState.commit_settings()
	)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	v.add_child(spacer)

	var back_row := UIStyle.make_menu_item("BACK", UIStyle.SIZE_BUTTON)
	UIStyle.button_of(back_row).pressed.connect(_on_back)
	v.add_child(back_row)

	# Esc also backs out.
	var forwarder := Node.new()
	forwarder.set_script(_InputForwarder)
	forwarder.set_meta("handler", func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_on_back()
	)
	add_child(forwarder)


func _on_back() -> void:
	GameState.commit_settings()
	closed.emit()
	queue_free()


func focus_first() -> void:
	if _first_focus != null:
		_first_focus.grab_focus()


# --- helpers ---

## Builds a row laid out as: [ NAME .......... CONTROL  VALUE ]
## The value Label is created last so it always sits at the end of the row.
func _make_row(parent: VBoxContainer, label_text: String, control: Control,
		value_text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var name_label := UIStyle.make_label(label_text, UIStyle.SIZE_BUTTON)
	name_label.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	row.add_child(name_label)

	control.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)

	var value := UIStyle.make_label(value_text, UIStyle.SIZE_BUTTON, UIStyle.COL_TEXT_BRIGHT)
	value.custom_minimum_size = Vector2(90, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	parent.add_child(row)
	return value


func _make_toggle() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(90, 0)
	b.flat = true
	b.add_theme_font_size_override("font_size", UIStyle.SIZE_BUTTON)
	_set_toggle(b, GameState.mouse_invert_y)
	return b


func _set_toggle(b: Button, on: bool) -> void:
	b.text = "ON" if on else "OFF"
	b.add_theme_color_override("font_color",
		UIStyle.COL_TEXT_BRIGHT if on else UIStyle.COL_TEXT_DIM)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIStyle.COL_PANEL_BG
	sb.border_color = UIStyle.COL_LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(36.0)
	return sb
