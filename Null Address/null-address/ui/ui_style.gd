extends RefCounted

## Shared visual language for the Null Address front-end.
##
## The whole UI is constructed in code rather than hand-authored .tscn files so
## that the look can be retuned from one place. Change a constant here and every
## screen follows.

# --- Palette: cold, desaturated, camcorder OSD over CRT glass ---
const COL_TEXT        := Color(0.78, 0.82, 0.84)
const COL_TEXT_DIM    := Color(0.40, 0.44, 0.46)
const COL_TEXT_BRIGHT := Color(1.00, 1.00, 1.00)
const COL_REC         := Color(0.88, 0.20, 0.18)
const COL_DONE        := Color(0.42, 0.72, 0.50)
const COL_LINE        := Color(1.00, 1.00, 1.00, 0.22)
const COL_PANEL_BG    := Color(0.02, 0.024, 0.028, 0.92)

# --- Type scale ---
const SIZE_TITLE  := 64
const SIZE_SUB    := 20
const SIZE_BUTTON := 30
const SIZE_OSD    := 18
const SIZE_SMALL  := 14


static func make_label(text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## A menu row = a fixed-width ">" cursor slot plus the button itself.
## Keeping the cursor in its own Label means the button text never shifts
## horizontally when focus moves (no jitter).
static func make_menu_item(base_text: String, font_size: int = SIZE_BUTTON) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var marker := Label.new()
	marker.text = ">"
	marker.add_theme_font_size_override("font_size", font_size)
	marker.add_theme_color_override("font_color", COL_REC)
	marker.custom_minimum_size = Vector2(20, 0)
	marker.modulate.a = 0.0
	row.add_child(marker)

	var b := Button.new()
	b.text = base_text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_TEXT_BRIGHT)
	b.add_theme_color_override("font_focus_color", COL_TEXT_BRIGHT)
	b.add_theme_color_override("font_pressed_color", COL_REC)
	b.add_theme_color_override("font_disabled_color", COL_TEXT_DIM)
	b.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.07)))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.88, 0.20, 0.18, 0.16)))
	b.add_theme_stylebox_override("focus", _flat(Color(1, 1, 1, 0.07)))
	b.add_theme_stylebox_override("disabled", _flat(Color(0, 0, 0, 0)))
	row.add_child(b)

	row.set_meta("button", b)
	row.set_meta("marker", marker)

	b.mouse_entered.connect(func() -> void: marker.modulate.a = 1.0)
	b.mouse_exited.connect(func() -> void: marker.modulate.a = 0.0)
	b.focus_entered.connect(func() -> void: marker.modulate.a = 1.0)
	b.focus_exited.connect(func() -> void: marker.modulate.a = 0.0)

	return row


static func button_of(row: HBoxContainer) -> Button:
	return row.get_meta("button") as Button


static func _flat(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb
