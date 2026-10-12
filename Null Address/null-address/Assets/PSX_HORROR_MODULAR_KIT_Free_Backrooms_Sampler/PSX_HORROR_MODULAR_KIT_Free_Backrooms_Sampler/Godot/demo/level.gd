extends Node3D
## Demo level of the PSX Horror Modular Kit (bitkiln - https://bitkiln.itch.io), painted with GridMaps.
##
## Keys besides the player's (see player.gd): P switches the PSX effects (vertex snapping, affine textures,
## 15-bit colour) of every kit material, K shows the next sky, H hides the help.
## Mood zones (env_zone.gd) fade the fog and the ambient light when the player walks into another area.

@export_multiline var help_text := ""
## Panorama skies for K (the first one is the sky of the scene).
@export var skies: Array[Texture2D] = []
## Outdoor fog colour that goes with each sky (the colour of its lower half, so the horizon disappears).
@export var sky_fog_colors := PackedColorArray()
## Outdoor ambient light energy for each sky.
@export var sky_ambient := PackedFloat32Array()
## Seconds for a mood change.
@export var fade_time := 1.2

var psx_on := true
var _sky := 0
var _inside: Array[Node] = []
var _outdoor := {}
var _tween: Tween

@onready var _env: Environment = ($WorldEnvironment as WorldEnvironment).environment
@onready var _help: Label = $HUD/Help


func _ready() -> void:
	_help.text = help_text
	_outdoor = {
		"fog_color": _env.fog_light_color,
		"fog_end": _env.fog_depth_end,
		"ambient_color": _env.ambient_light_color,
		"ambient_energy": _env.ambient_light_energy,
		"show_sky": _env.background_mode == Environment.BG_SKY,
	}
	for zone in get_tree().get_nodes_in_group("env_zones"):
		var area := zone as Area3D
		area.body_entered.connect(_on_zone_entered.bind(area))
		area.body_exited.connect(_on_zone_exited.bind(area))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_P:
			set_psx(not psx_on)
		KEY_K:
			next_sky()
		KEY_H:
			_help.visible = not _help.visible
		_:
			return
	get_viewport().set_input_as_handled()


## Switches vertex snapping, affine texture mapping and 15-bit colour on every material of the level.
func set_psx(on: bool) -> void:
	psx_on = on
	for m in kit_materials():
		m.set_shader_parameter("vertex_snap", on)
		m.set_shader_parameter("affine_strength", 1.0 if on else 0.0)
		m.set_shader_parameter("color_15bit", on)
		m.set_shader_parameter("dithering", on)


## Every PSX ShaderMaterial used by the GridMaps, the doors and the ground of this level.
func kit_materials() -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for node in find_children("*", "GridMap", true, false):
		var lib := (node as GridMap).mesh_library
		if lib == null:
			continue
		for id in lib.get_item_list():
			_add_mesh_materials(lib.get_item_mesh(id), found)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_add_mesh_materials(mi.mesh, found)
		var m := mi.material_override as ShaderMaterial
		if m != null and not found.has(m):
			found.append(m)
	return found


func _add_mesh_materials(mesh: Mesh, found: Array[ShaderMaterial]) -> void:
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s) as ShaderMaterial
		if m != null and not found.has(m):
			found.append(m)


## Shows the next panorama sky and gives the outdoor fog its colour.
func next_sky() -> void:
	if skies.is_empty() or _env.sky == null:
		return
	_sky = (_sky + 1) % skies.size()
	var mat := _env.sky.sky_material as PanoramaSkyMaterial
	if mat != null:
		mat.panorama = skies[_sky]
	if _sky < sky_fog_colors.size():
		_outdoor["fog_color"] = sky_fog_colors[_sky]
	if _sky < sky_ambient.size():
		_outdoor["ambient_energy"] = sky_ambient[_sky]
	_apply()


func _on_zone_entered(body: Node, zone: Area3D) -> void:
	if body.is_in_group("player"):
		_inside.erase(zone)
		_inside.append(zone)
		_apply()


func _on_zone_exited(body: Node, zone: Area3D) -> void:
	if body.is_in_group("player"):
		_inside.erase(zone)
		_apply()


func _apply() -> void:
	var mood := _outdoor
	if not _inside.is_empty():
		var z := _inside.back() as Node
		mood = {
			"fog_color": z.get("fog_color"),
			"fog_end": z.get("fog_end"),
			"ambient_color": z.get("ambient_color"),
			"ambient_energy": z.get("ambient_energy"),
			"show_sky": z.get("show_sky"),
		}
	if _tween != null:
		_tween.kill()
	_env.background_mode = Environment.BG_SKY if mood["show_sky"] and _env.sky != null else Environment.BG_COLOR
	_tween = create_tween().set_parallel()
	_tween.tween_property(_env, "fog_light_color", mood["fog_color"], fade_time)
	_tween.tween_property(_env, "background_color", mood["fog_color"], fade_time)
	_tween.tween_property(_env, "fog_depth_end", mood["fog_end"], fade_time)
	_tween.tween_property(_env, "ambient_light_color", mood["ambient_color"], fade_time)
	_tween.tween_property(_env, "ambient_light_energy", mood["ambient_energy"], fade_time)
