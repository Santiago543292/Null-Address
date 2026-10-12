extends Node3D
## Hunt demo of PSX Horror Monsters (bitkiln - https://bitkiln.itch.io).
##
## A dark maze with the monsters of the pack in it. They wander around, notice you when you come into view,
## follow you around the walls (NavigationAgent3D on the navigation mesh baked at start) and attack.
## Shoot them with the left mouse button.
##   P PSX shader on / off    G god mode (monsters cannot hurt you)    N every monster hunts you
##   R restart                H help
## The player keys are in scripts/player.gd (WASD, mouse, Shift sprint, F flashlight, Esc frees the mouse).

const PSX := preload("res://shaders/apply_psx.gd")
const HELP := "WASD move   mouse look (click)   Shift sprint   Space jump   F flashlight   left click shoot\n" + \
		"P PSX shader   G god mode   N wake every monster   R restart   H help   Esc free the mouse"

@export var psx_enabled := true
## Bake the navigation mesh of the Navigation node when the scene starts (the maze builds itself on load).
@export var bake_navigation := true

var _monsters: Array[MonsterBrain] = []
var _alive := 0
var _counter: Label
var _help: Label
var _message: Label

@onready var _player := $Player as CharacterBody3D
@onready var _navigation := $Navigation as NavigationRegion3D


func _ready() -> void:
	if bake_navigation and _navigation != null and _navigation.navigation_mesh != null:
		_navigation.bake_navigation_mesh(false)
	for node in $Monsters.get_children():
		var monster := node as MonsterBrain
		if monster == null:
			continue
		_monsters.append(monster)
		monster.died.connect(_on_monster_died)
	_alive = _monsters.size()
	_build_hud()
	set_psx(psx_enabled)
	_update_hud()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	_counter = _label(hud, 24, Control.PRESET_TOP_RIGHT)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help = _label(hud, 15, Control.PRESET_TOP_LEFT)
	_help.text = HELP
	_help.offset_top = 52.0
	_help.modulate = Color(1, 1, 1, 0.8)
	_message = _label(hud, 30, Control.PRESET_CENTER)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message.position.y += 60.0


func _label(parent: Node, size: int, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.93, 0.87, 0.78))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	return label


## Turns the PSX shader on or off for the whole level.
func set_psx(on: bool) -> void:
	psx_enabled = on
	if on:
		PSX.apply(self)
	else:
		PSX.restore(self)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_P:
			set_psx(not psx_enabled)
		KEY_G:
			if _player != null:
				_player.set("invulnerable", not bool(_player.get("invulnerable")))
		KEY_N:
			for monster in _monsters:
				if not monster.is_dead():
					monster.hunt(_player)
		KEY_R:
			get_tree().reload_current_scene()
			return
		KEY_H:
			_help.visible = not _help.visible
		_:
			return
	_update_hud()
	get_viewport().set_input_as_handled()


func _on_monster_died() -> void:
	_alive = 0
	for monster in _monsters:
		if not monster.is_dead():
			_alive += 1
	_update_hud()
	if _alive == 0:
		_message.text = "Every monster is down.\nPress R to play again."


func _update_hud() -> void:
	if _counter == null:
		return
	var god := _player != null and bool(_player.get("invulnerable"))
	_counter.text = "MONSTERS %d / %d%s\nPSX shader %s" % [_alive, _monsters.size(), "   GOD MODE" if god else "",
			"ON" if psx_enabled else "OFF"]
