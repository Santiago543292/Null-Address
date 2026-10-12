extends Node3D

## A pickable lamp post.
##
## Looks and behaves like every other lamp: warm white, steady. At random
## intervals the ODD ONE OUT turns red for a moment, then goes back to normal -
## the player has to spot which lamp does it and press E on it.
##
## Attach to a Lamp_N node (which has Pole, Bulb, Light children). The script
## adds its own collision and interaction area, so the existing lamps need no
## editing beyond attaching this and giving them a PuzzleManager.

@export_group("Look")
## The normal, boring colour. Every lamp is this.
@export var color_normal := Color(1.0, 0.86, 0.64)
## The tells. Only the odd one out ever uses these, and it alternates between
## them so the pattern is harder to pin down.
@export var color_tell := Color(0.92, 0.12, 0.10)      # red
@export var color_tell_alt := Color(0.62, 0.16, 0.92)  # purple
## Energy while steady.
@export var energy_normal := 3.6
## Energy while showing the tell.
@export var energy_tell := 5.4
## How long the red flash lasts, in seconds.
@export var tell_seconds := 0.55

@export_group("Interaction")
## How close the player must be to press E on it.
@export var interact_radius := 3.2
## Prompt shown while in range.
@export var prompt := "CHECK LAMP"

var is_the_one := false
var _light: OmniLight3D
var _bulb: MeshInstance3D
var _bulb_mat: StandardMaterial3D
var _area: Area3D
var _player_near := false
var _telling := false
var _tell_left := 0.0
var _flip := false
var _tell_colour := Color(1, 0, 0)
var _manager: Node


func _ready() -> void:
	_light = get_node_or_null("Light") as OmniLight3D
	_manager = _find_manager()

	# Rebuild the visible geometry: base, pole, collar, bracket arm, hood and a
	# lens. This also creates `_bulb` (the Lens mesh) with its own material, so
	# the puzzle can recolour this lamp without touching the other eleven.
	_rebuild_look()

	# the light hangs where the lens is, not at the pole's centre
	if _light != null:
		_light.position = Vector3(0.72, 3.24, 0.0)

	_build_collision()
	_build_interact_area()
	_reset_look()


## The LampPuzzle manager. It is a SIBLING of LampPosts, not the scene root -
## get_parent().get_parent() returned HUBsc, which has no lamp_entered_range, so
## proximity was tracked locally and the manager was never told. That is exactly
## why the prompt never appeared and E did nothing.
func _find_manager() -> Node:
	var root := get_parent().get_parent() if get_parent() != null else null
	if root == null:
		return null
	var by_name := root.get_node_or_null("LampPuzzle")
	if by_name != null and by_name.has_method("lamp_entered_range"):
		return by_name
	# fall back: any sibling that can receive our callbacks
	for c in root.get_children():
		if c.has_method("lamp_entered_range"):
			return c
	return null


## A solid pole so the player cannot walk through the lamp, plus a small cap so
## it does not float.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "LampBody"
	add_child(body)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.28
	cyl.height = 3.4
	shape.shape = cyl
	shape.position = Vector3(0, 1.7, 0)
	body.add_child(shape)


## Rebuild the lamp's visible geometry so it reads as street furniture.
##
## The scene's lamps are a bare cylinder and a floating sphere - a pole with a
## ball on it. Real street lamps have a base, a bracket arm, a housing with a
## hood, and a lens that is visibly the thing glowing. All of that is built here
## in code so the twelve instances need no scene edits, and the puzzle's
## recolouring keeps working because it drives the LIGHT and the lens material.
func _rebuild_look() -> void:
	# remove the placeholder geometry (Pole / Bulb), keep collision + interact
	for c in get_children():
		if c is MeshInstance3D:
			remove_child(c)
			c.queue_free()

	var metal := _metal_mat()
	var lens := _lens_mat()

	# --- base: a plinth so the pole is not growing out of the ground ---
	var base := CylinderMesh.new()
	base.top_radius = 0.20
	base.bottom_radius = 0.26
	base.height = 0.34
	base.radial_segments = 10
	base.material = metal
	_add_mesh("Base", base, Vector3(0, 0.17, 0))

	# --- pole ---
	var pole := CylinderMesh.new()
	pole.top_radius = 0.055
	pole.bottom_radius = 0.085
	pole.height = 3.30
	pole.radial_segments = 8
	pole.material = metal
	_add_mesh("Pole", pole, Vector3(0, 0.34 + 3.30 * 0.5, 0))

	# --- collar where the arm meets the pole ---
	var collar := CylinderMesh.new()
	collar.top_radius = 0.10
	collar.bottom_radius = 0.11
	collar.height = 0.16
	collar.radial_segments = 8
	collar.material = metal
	_add_mesh("Collar", collar, Vector3(0, 3.48, 0))

	# --- bracket arm: a horizontal cylinder reaching out from the top ---
	var arm_len := 0.72
	var arm := CylinderMesh.new()
	arm.top_radius = 0.042
	arm.bottom_radius = 0.052
	arm.height = arm_len
	arm.radial_segments = 6
	arm.material = metal
	var arm_pos := Vector3(arm_len * 0.5, 3.56, 0.0)
	# a cylinder's axis is +Y, so lay it along +X by rotating about Z
	_add_mesh_rot("Arm", arm, arm_pos, Vector3(0, 0, deg_to_rad(90)))

	# --- housing: a hood over the lens ---
	var hood := CylinderMesh.new()
	hood.top_radius = 0.24
	hood.bottom_radius = 0.30
	hood.height = 0.20
	hood.radial_segments = 10
	hood.material = metal
	_add_mesh("Hood", hood, Vector3(arm_len, 3.50, 0.0))

	# --- the lens: this is the thing the puzzle recolours ---
	var lens_mesh := SphereMesh.new()
	lens_mesh.radius = 0.17
	lens_mesh.height = 0.30
	lens_mesh.radial_segments = 10
	lens_mesh.rings = 5
	lens_mesh.material = lens
	var lens_node := _add_mesh("Lens", lens_mesh, Vector3(arm_len, 3.30, 0.0))
	_bulb = lens_node            # the puzzle drives this mesh's material

	# --- finial on top of the hood ---
	var fin := SphereMesh.new()
	fin.radius = 0.055
	fin.height = 0.11
	fin.radial_segments = 6
	fin.rings = 4
	fin.material = metal
	_add_mesh("Finial", fin, Vector3(arm_len, 3.63, 0.0))


func _metal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.085, 0.09, 0.10)
	m.metallic = 0.8
	m.roughness = 0.45
	return m


func _lens_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color_normal
	m.emission_enabled = true
	m.emission = color_normal
	m.emission_energy_multiplier = 1.6
	m.roughness = 0.3
	# stored so _reset_look() and flash_tell() can recolour the lens without
	# touching the other eleven lamps' materials
	_bulb_mat = m
	return m


func _add_mesh(nm: String, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	return _add_mesh_rot(nm, mesh, pos, Vector3.ZERO)


func _add_mesh_rot(nm: String, mesh: Mesh, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


## The area the player stands in to press E.
func _build_interact_area() -> void:
	_area = Area3D.new()
	_area.name = "InteractArea"
	# Set the mask EXPLICITLY. Leaving it at the default relied on the player
	# also being on layer 1, and a silent mismatch there is exactly how "the key
	# does nothing" happens.
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true
	add_child(_area)

	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interact_radius
	cs.shape = sphere
	cs.position = Vector3(0, 1.4, 0)
	_area.add_child(cs)

	_area.body_entered.connect(_on_near)
	_area.body_exited.connect(_on_far)


func _on_near(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_player_near = true
	if _manager != null and _manager.has_method("lamp_entered_range"):
		_manager.call("lamp_entered_range", self)


func _on_far(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_player_near = false
	if _manager != null and _manager.has_method("lamp_left_range"):
		_manager.call("lamp_left_range", self)


## Show the red tell for a moment. Only the odd one out is ever told to.
func flash_tell() -> void:
	if _light == null:
		return
	_telling = true
	_tell_left = tell_seconds
	# alternate red / purple so the tell is not one fixed colour
	_tell_colour = color_tell if _flip else color_tell_alt
	_flip = not _flip
	_light.light_color = _tell_colour
	_light.light_energy = energy_tell
	if _bulb_mat != null:
		_bulb_mat.albedo_color = _tell_colour
		_bulb_mat.emission = _tell_colour


func _process(delta: float) -> void:
	if not _telling:
		return
	_tell_left -= delta
	if _tell_left <= 0.0:
		_telling = false
		_reset_look()


## Back to the boring warm white every lamp has.
func _reset_look() -> void:
	if _light != null:
		_light.light_color = color_normal
		_light.light_energy = energy_normal
	if _bulb_mat != null:
		_bulb_mat.albedo_color = color_normal
		_bulb_mat.emission = color_normal


## Mark this lamp as the one the player must find.
func make_the_one() -> void:
	is_the_one = true


## Hold the red on permanently, once the player has found it.
func hold_tell() -> void:
	flash_tell()
	_tell_left = 1e9


func is_near() -> bool:
	return _player_near
