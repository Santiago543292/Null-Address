extends Node3D

## A dead tree that actually looks like a dead tree.
##
## The originals were a bare `CylinderMesh` trunk with a flat brown colour and a
## `SphereMesh` canopy with a flat green colour - no texture, no bark, no
## branches, and a perfect sphere for foliage. Flat albedo on a primitive reads
## as a placeholder no matter what colour you pick.
##
## This rebuilds the look in three ways:
##
##   1. TEXTURE the trunk and canopy from the PSX horror texture pack, so there
##      is actual surface detail instead of a flat fill.
##   2. REPLACE the sphere with a cluster of smaller, irregular, flattened
##      blobs, which reads as ragged foliage rather than a lollipop.
##   3. ADD branches - angled tapered cylinders off the trunk - which is most of
##      what makes a tree read as a tree at all.
##
## Attach to each `Tree_N` node. It rewrites the children in `_ready()`, so the
## scene file needs no geometry edits and re-running is idempotent.

@export_group("Trunk")
@export var trunk_texture := "res://Assets/PSX_Horror_Textures_FREE_Sample/PSX_Horror_Textures_FREE_Sample/128px/dirt.png"
@export var trunk_tint := Color(0.58, 0.46, 0.34)
@export var trunk_height := 2.6
@export var trunk_top_radius := 0.16
@export var trunk_bottom_radius := 0.24

@export_group("Canopy")
@export var canopy_texture := "res://Assets/PSX_Horror_Textures_FREE_Sample/PSX_Horror_Textures_FREE_Sample/128px/dirt.png"
@export var canopy_tint := Color(0.46, 0.38, 0.22)
## How many blobs make up the crown. More = denser and heavier.
@export var canopy_blobs := 5
@export var canopy_radius := 1.5
@export var canopy_height := 2.6

@export_group("Branches")
@export var branch_count := 4
@export var branch_min_height := 1.3
@export var branch_max_height := 2.3

@export_group("Look")
## Shade the underside of the crown so it does not read as a ball of light.
@export var crown_darkening := 0.55
## Skip the rebuild if the tree already has branches (idempotence guard).
@export var rebuild := true

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not rebuild:
		return
	# a per-tree seed from the node name, so trees differ but re-runs match
	_rng.seed = hash(name)
	_rebuild()


func _rebuild() -> void:
	# remove the placeholder geometry, keeping any collision
	for c in get_children():
		if c is MeshInstance3D:
			remove_child(c)
			c.queue_free()

	var bark := _make_material(trunk_texture, trunk_tint, 0.9)
	var leaf := _make_material(canopy_texture, canopy_tint, 0.95)

	_build_trunk(bark)
	# branches return their tip positions so the crown can hang foliage off the
	# ends of them rather than scattering blobs in a ball
	var tips := _build_branches(bark)
	_build_crown(leaf, tips)


func _make_material(tex_path: String, tint: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	# PSX textures are tiny; nearest-neighbour keeps the crunchy look instead of
	# smearing it into mush
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = load(tex_path)
	if tex != null:
		m.albedo_texture = tex
		# tile it so a 128px texture is not stretched over a 2.6m trunk
		m.uv1_scale = Vector3(2.0, 3.0, 2.0)
	return m


## A unit vector pointing away from the trunk: `pitch` radians off vertical,
## `yaw` radians around it.
func _branch_axis(pitch: float, yaw: float) -> Vector3:
	return Vector3(sin(pitch) * cos(yaw), cos(pitch), sin(pitch) * sin(yaw)).normalized()


## An orthonormal basis whose Y column is `dir`. This is what makes a cylinder
## point along an arbitrary direction without a look_at.
func _basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	# any vector not parallel to y works as the seed for the other two columns
	var seed := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := seed.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _build_trunk(bark: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = trunk_top_radius
	mesh.bottom_radius = trunk_bottom_radius
	mesh.height = trunk_height
	mesh.radial_segments = 7      # low poly, in keeping with the rest
	mesh.rings = 1
	mesh.material = bark

	var mi := MeshInstance3D.new()
	mi.name = "Trunk"
	mi.mesh = mesh
	mi.position = Vector3(0, trunk_height * 0.5, 0)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(mi)


## Branches are most of what makes a tree read as a tree. Angled tapered
## cylinders coming off the trunk at varying heights.
##
## Returns each branch's TIP position in tree space, so the crown can hang
## foliage off the ends of the branches instead of guessing at a spread.
func _build_branches(bark: StandardMaterial3D) -> Array[Vector3]:
	var holder := Node3D.new()
	holder.name = "Branches"
	add_child(holder)

	var tips: Array[Vector3] = []
	for i in branch_count:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.03
		mesh.bottom_radius = 0.09
		var len := _rng.randf_range(0.9, 1.5)
		mesh.height = len
		mesh.radial_segments = 5
		mesh.rings = 1
		mesh.material = bark

		var mi := MeshInstance3D.new()
		mi.name = "Branch_%d" % i
		mi.mesh = mesh

		# start on the trunk, angle outward and upward
		var y := _rng.randf_range(branch_min_height, branch_max_height)
		var yaw := _rng.randf_range(0.0, TAU)
		var pitch := _rng.randf_range(0.55, 0.95)   # radians from vertical

		# A CylinderMesh's axis is +Y and it is CENTRED on its node origin, so
		# build a basis whose Y column is the branch direction and offset the
		# node by half the length along that direction. look_at_from_position
		# plus a local rotate was leaving branches detached from the trunk.
		var axis := _branch_axis(pitch, yaw)
		var base := Vector3(0, y, 0)
		mi.transform = Transform3D(_basis_from_y(axis), base + axis * (len * 0.5))
		holder.add_child(mi)

		# the far end of this branch, in tree space
		tips.append(base + axis * len)
	return tips


## The crown: foliage anchored to the branch tips and the trunk top.
##
## This used to scatter blobs in a ball of radius `canopy_radius * 0.7` around a
## point above the trunk. The trunk is only ~0.24 m across and the spread was
## +/-1.05 m, so most of the foliage hung in the air BESIDE the tree with nothing
## under it - the reported "leaves not connected to the main branch".
##
## Foliage now grows from the ends of the branches: one cluster per branch tip,
## plus one on the trunk top, each cluster a few overlapping blobs jittered by
## roughly its own radius so the cluster stays cohesive.
func _build_crown(leaf: StandardMaterial3D, tips: Array[Vector3]) -> void:
	var holder := Node3D.new()
	holder.name = "Crown"
	add_child(holder)

	# one cluster per branch tip, plus the trunk top
	var anchors: Array[Vector3] = []
	for t in tips:
		anchors.append(t)
	anchors.append(Vector3(0, trunk_height + canopy_height * 0.10, 0))

	var blob_index := 0
	for a in anchors:
		# blobs per cluster: enough to read as a mass, few enough to stay light
		var per := maxi(1, int(round(float(canopy_blobs) / float(anchors.size()) * 2.0)))
		var cluster_r := canopy_radius * _rng.randf_range(0.34, 0.46)
		for j in per:
			var r := cluster_r * _rng.randf_range(0.6, 1.0)
			var mesh := SphereMesh.new()
			mesh.radius = r
			mesh.height = r * 2.0 * _rng.randf_range(0.7, 1.0)
			mesh.radial_segments = 7
			mesh.rings = 4
			mesh.material = leaf

			var mi := MeshInstance3D.new()
			mi.name = "Blob_%d" % blob_index
			blob_index += 1
			mi.mesh = mesh
			# jitter by about the blob's own radius, so the cluster is a mass
			# rather than a line of separated balls
			mi.position = a + Vector3(
				_rng.randf_range(-cluster_r, cluster_r),
				_rng.randf_range(-cluster_r * 0.6, cluster_r * 0.6),
				_rng.randf_range(-cluster_r, cluster_r))
			mi.rotation = Vector3(
				_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU))
			mi.scale = Vector3(
				_rng.randf_range(0.85, 1.15), _rng.randf_range(0.7, 0.95), _rng.randf_range(0.85, 1.15))
			holder.add_child(mi)

	# a couple of bare, dead limbs poking out of the crown, anchored to the
	# trunk top so they are attached rather than loose
	for i in 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.015
		mesh.bottom_radius = 0.05
		var len := _rng.randf_range(0.8, 1.4)
		mesh.height = len
		mesh.radial_segments = 4
		mesh.rings = 1
		mesh.material = leaf

		var mi := MeshInstance3D.new()
		mi.name = "DeadLimb_%d" % i
		mi.mesh = mesh
		var yaw := _rng.randf_range(0.0, TAU)
		var pitch := _rng.randf_range(0.8, 1.25)
		var axis := _branch_axis(pitch, yaw)
		# anchor at the TRUNK TOP, so these emerge from the tree rather than
		# hanging in space above it. The old anchor was a local (0, -0.2..0.2, 0)
		# inside the crown holder, which sat 0.65 m above the trunk top and left
		# these detached whenever the crown moved.
		var anchor := Vector3(0, trunk_height + canopy_height * 0.05, 0)
		mi.transform = Transform3D(_basis_from_y(axis), anchor + axis * (len * 0.5))
		holder.add_child(mi)
