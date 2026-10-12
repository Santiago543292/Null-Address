extends Node3D

## FURNISHED INTERIOR for a HUB house.
##
## The twelve hub houses ship as empty shells - floor, walls, roof, nothing else.
## This fills one with furniture and, importantly, with a HIDING SPOT.
##
## Attach to a `House_N` instance in HUBsc.tscn. Everything is built in code and
## positioned from the house's own measured interior, so it needs no scene edits
## and survives the house being moved.
##
## HIDING: the watcher cannot find a player who is inside a hiding spot. This
## script registers its hiding volume with the hub's HidingSpot registry, which
## the watcher reads before it makes a cue. Without that link, "hide" is just a
## pose - the monster keeps finding you and the mechanic is a lie.

@export_group("Interior")
## Interior of house_1.tscn measured from its floor mesh AABB: 4.0 x 6.0 m,
## floor top at y = 1.0. Half-extents are used to keep furniture off the walls.
@export var interior_half_x := 1.75
@export var interior_half_z := 2.75
## The floor's top surface, in house-local space.
@export var floor_y := 1.0
## How far off a wall furniture sits.
@export var wall_inset := 0.45

@export_group("Hiding")
## Build a hiding spot (a wardrobe/alcove the player can duck into).
@export var make_hiding_spot := true
## How long the player must stay still in it before they count as hidden.
@export var hide_dwell := 1.2
## Which side the hiding spot goes on.
@export var hiding_side := 3

## The wardrobe used as the hiding spot.
const HIDING_PROP := "res://Assets/KayKit_Furniture_Bits_1.0_FREE/KayKit_Furniture_Bits_1.0_FREE/Assets/gltf/cabinet_medium.gltf"

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if make_hiding_spot:
		_build_hiding_spot()


## A wardrobe with an interior volume the player can step into and hide.
func _build_hiding_spot() -> void:
	var ps: PackedScene = load(HIDING_PROP)
	if ps == null:
		return

	var holder := Node3D.new()
	holder.name = "HidingSpot"
	add_child(holder)

	var hx := interior_half_x - wall_inset
	var hz := interior_half_z - wall_inset
	var pos := Vector3.ZERO
	var yaw := 0.0
	match hiding_side:
		0:
			pos = Vector3(0.0, 0.0, -hz)
			yaw = 0.0
		1:
			pos = Vector3(0.0, 0.0, hz)
			yaw = 180.0
		2:
			pos = Vector3(-hx, 0.0, 0.0)
			yaw = 90.0
		_:
			pos = Vector3(hx, 0.0, 0.0)
			yaw = 270.0

	var inst := ps.instantiate() as Node3D
	if inst != null:
		inst.name = "Wardrobe"
		inst.position = Vector3(pos.x, floor_y - 0.02, pos.z)
		inst.rotation_degrees = Vector3(0.0, yaw, 0.0)
		holder.add_child(inst)

	# The volume that counts as "hidden". Slightly larger than the wardrobe so a
	# player standing in the doorway of it still registers.
	var area := Area3D.new()
	area.name = "HideArea"
	area.collision_layer = 0
	area.collision_mask = 1          # detect the player on layer 1
	area.monitoring = true
	area.position = Vector3(pos.x, floor_y + 0.9, pos.z)
	add_child(area)

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.9, 1.4)
	cs.shape = box
	area.add_child(cs)

	# register with the hub's hiding registry so the watcher respects it
	var reg := _find_registry()
	if reg != null and reg.has_method("register"):
		reg.call("register", area, hide_dwell)


## The hiding registry lives on the HUB ROOT, which is NOT our parent.
##
## This node is a child of `Houses`, and `HidingSpots` is a sibling of `Houses`,
## so `get_parent()` is one level too high - the original version looked for the
## registry among `Houses`' children, found nothing, and every house silently
## registered zero hiding spots. Walk up to the scene root instead.
func _find_registry() -> Node:
	# `var node := self` infers the script's OWN class (house_interior.gd), so
	# assigning a parent Node3D to it fails with "Trying to assign value of type
	# 'Node3D' to a variable of type 'house_interior.gd'". Type it as Node.
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	if node == null:
		return null
	var direct := node.get_node_or_null("HidingSpots")
	if direct != null and direct.has_method("register"):
		return direct
	# fall back: any node at the root that can register and answer
	for c in node.get_children():
		if c.has_method("register") and c.has_method("is_hidden"):
			return c
	return null
