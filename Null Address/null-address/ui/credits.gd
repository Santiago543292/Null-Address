extends Control

## CREDITS - everyone whose work is in this game.
##
## Built from CREDITS below, so adding an asset pack means adding one row here,
## not editing the screen.
##
## Licence note: most of these are CC0 (no attribution legally required) and one
## is CC BY 4.0 (attribution REQUIRED). They are all credited anyway - it costs
## nothing and it is the decent thing to do. The `required` flag marks the ones
## whose licence actually demands it, so that is never accidentally dropped.

const UIStyle := preload("res://ui/ui_style.gd")

const ROW_H := 62

## name, what they made, licence, url, attribution_required
const CREDITS: Array[Dictionary] = [
	{
		"name": "Kay Lousberg",
		"work": "KayKit - Dungeon, Furniture, Halloween and Prototype Bits",
		"licence": "CC0 1.0",
		"url": "https://kaylousberg.itch.io",
		"required": false,
	},
	{
		"name": "Quaternius",
		"work": "Ultimate Platformer Pack, Downtown City MegaKit",
		"licence": "CC0 1.0",
		"url": "https://quaternius.com",
		"required": false,
	},
	{
		"name": "bitkiln",
		"work": "PSX Horror Modular Kit, Props, Monsters and Textures (free samplers)",
		"licence": "free for commercial use, credit appreciated",
		"url": "https://bitkiln.itch.io",
		"required": false,
	},
	{
		"name": "heyheythere",
		"work": "PSX Creatures Free - Monsters Sampler",
		"licence": "CC BY 4.0",
		"url": "https://heyheythere.itch.io/psx-creatures-free",
		"required": true,
	},
	{
		"name": "Madduck",
		"work": "Free Modular 3D Hospital Environment",
		"licence": "free for commercial use",
		"url": "https://madduck.itch.io/modular-3d-hospital-environment",
		"required": false,
	},
	{
		"name": "Loafbrr",
		"work": "House and Props Pack, Wood Stuff",
		"licence": "see pack",
		"url": "https://loafbrr.itch.io",
		"required": false,
	},
	{
		"name": "Kenney",
		"work": "Starter Kit and furniture assets",
		"licence": "CC0 1.0",
		"url": "https://kenney.nl",
		"required": false,
	},
	{
		"name": "ENTROPYSTARTER",
		"work": "Music - after hours, deja vu, echoes, internal monologue, simulation",
		"licence": "see pack",
		"url": "",
		"required": false,
	},
	{
		"name": "Park Bird & Reponix",
		"work": "Music - Are You Lost (main menu)",
		"licence": "see track",
		"url": "",
		"required": false,
	},
	{
		"name": "Dreamcorp",
		"work": "Music - Nevermind Everything's Ok (in-game)",
		"licence": "see track",
		"url": "",
		"required": false,
	},
]

var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Music.play_menu()
	_build()
	GameState.set_gameplay_mouse(false)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.90)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(UIStyle.make_label("CREDITS", 64, UIStyle.COL_TEXT_BRIGHT))
	col.add_child(UIStyle.make_label(
		"Null Address is built with other people's work. Thank you.",
		22, UIStyle.COL_TEXT_DIM))

	var rule := ColorRect.new()
	rule.color = Color(UIStyle.COL_TEXT_DIM.r, UIStyle.COL_TEXT_DIM.g,
		UIStyle.COL_TEXT_DIM.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	# the list scrolls, so it stays usable as more packs are added
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	_populate()

	var back := Button.new()
	back.flat = false
	back.focus_mode = Control.FOCUS_ALL
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.custom_minimum_size = Vector2(0, 50)
	back.add_child(UIStyle.make_label("ESC  /  click here to go back", 22,
		UIStyle.COL_TEXT_DIM))
	back.pressed.connect(_back)
	col.add_child(back)


func _populate() -> void:
	for c in CREDITS:
		_list.add_child(_make_row(c))


func _make_row(c: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.add_theme_constant_override("separation", 0)

	# line 1: name  +  licence
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(UIStyle.make_label(str(c["name"]), 30, UIStyle.COL_TEXT_BRIGHT))

	var lic := str(c.get("licence", ""))
	if bool(c.get("required", false)):
		# attribution is a licence condition for this one, so mark it
		top.add_child(UIStyle.make_label("attribution required  -  " + lic,
			18, UIStyle.COL_REC))
	else:
		top.add_child(UIStyle.make_label(lic, 18, UIStyle.COL_DONE))
	row.add_child(top)

	# line 2: what they made
	row.add_child(UIStyle.make_label(str(c["work"]), 20, UIStyle.COL_TEXT))

	# line 3: link
	var url := str(c.get("url", ""))
	if url != "":
		var link := LinkButton.new()
		link.text = url
		link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		link.uri = url
		link.add_theme_font_size_override("font_size", 18)
		link.add_theme_color_override("font_color", UIStyle.COL_TEXT_DIM)
		link.add_theme_color_override("font_hover_color", UIStyle.COL_TEXT_BRIGHT)
		row.add_child(link)

	return row


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	GameState.set_gameplay_mouse(false)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
