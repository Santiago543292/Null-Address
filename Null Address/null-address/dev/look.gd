extends Node

## Renders the hub so it can actually be LOOKED at, and measures grounding.
## Windowed only - there is no renderer under --headless.

@export var out_dir := "C:/Users/Santi/AppData/Local/hermes/cache/scratch/look"

var _fixes: Array[String] = []
var _ok := 0
var _on_top := 0

const SKIP := ["Ground", "Ground2", "Boundary", "Skyline", "DoorSlab", "back_wall",
	"back_pillar", "Sign", "ActDoor", "Ceiling", "Wall", "Zone"]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	for i in range(90):
		await get_tree().process_frame
	for i in range(12):
		await get_tree().physics_frame

	var root := get_parent()
	var space := get_viewport().world_3d.direct_space_state

	print("=== GROUNDING ===")
	for m in _all(root, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.top_level or not mi.visible: continue
		var skip := false
		for sk in SKIP:
			if mi.name.begins_with(sk): skip = true
		if skip: continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		if box.size.x > 40.0 or box.size.z > 40.0 or box.size.y > 30.0: continue
		var c := box.get_center()
		var bottom := box.position.y
		if bottom < -0.5: continue
		var q := PhysicsRayQueryParameters3D.new()
		q.from = Vector3(c.x, bottom + 0.35, c.z)
		q.to = Vector3(c.x, bottom - 6.0, c.z)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit.is_empty(): continue
		var surface_y: float = hit["position"].y
		var gap := bottom - surface_y
		var hn := ""
		if hit.get("collider") != null: hn = str(hit["collider"].name)
		if gap <= 0.07:
			_ok += 1
		elif hn.begins_with("Ground") or hn.begins_with("Boundary"):
			if gap <= 1.6:
				_fixes.append("%s|%.2f|%.2f|%.2f" % [_path_of(mi, root), bottom, surface_y, gap])
		else:
			_on_top += 1

	print("  grounded %d | on props %d | FLOATING %d" % [_ok, _on_top, _fixes.size()])
	for f in _fixes.slice(0, 40):
		var a: PackedStringArray = str(f).split("|")
		print("    SNAP %-34s y %.2f -> %.2f (gap %.2f)" % [a[0], float(a[1]), float(a[2]), float(a[3])])
	print("SNAP_TOTAL: %d" % _fixes.size())

	# --- tree inventory, to prove the rebuild ran ---
	var trees := root.get_node_or_null("Scatter/Trees")
	if trees != null:
		var t0 := trees.get_child(0)
		var meshes := _all(t0, "MeshInstance3D")
		var with_tex := 0
		for m in meshes:
			var mm := (m as MeshInstance3D).mesh
			if mm != null and mm.get_surface_count() > 0:
				var mat := mm.surface_get_material(0) as BaseMaterial3D
				if mat != null and mat.albedo_texture != null: with_tex += 1
		print("=== TREES ===")
		print("  %s: %d meshes, %d textured" % [t0.name, meshes.size(), with_tex])
		var branches := t0.get_node_or_null("Branches")
		var crown := t0.get_node_or_null("Crown")
		print("  branches: %d" % (branches.get_child_count() if branches else 0))
		print("  crown blobs: %d" % (crown.get_child_count() if crown else 0))

	# hide the HUD - its title card covers the middle of every shot and made the
	# vision pass describe the images as "a title screen"
	var hud := root.get_node_or_null("HubHUD")
	if hud != null and hud is CanvasLayer:
		(hud as CanvasLayer).visible = false

	# --- render ---
	var body := _body(root)
	var cam := _camera(body) if body != null else null
	if cam != null:
		cam.top_level = true
		# aim at real tree positions rather than guessed coordinates
		var tree_holder := root.get_node_or_null("Scatter/Trees")
		var views: Array = []
		if tree_holder != null and tree_holder.get_child_count() > 0:
			for i in range(min(4, tree_holder.get_child_count())):
				var t := tree_holder.get_child(i) as Node3D
				var p := t.global_position
				views.append(["04_tree%d" % i, p + Vector3(3.0, 2.2, 3.0), p + Vector3(0, 2.6, 0)])
		if views.is_empty():
			views.append(["04_trees", Vector3(-14, 2.4, -38), Vector3(-18, 2.0, -44)])
		views.append_array([
			["01_wide",     Vector3(0, 6, 26),     Vector3(0, 1, 0)],
			["02_ground",   Vector3(5, 1.1, 9),    Vector3(18, 0.4, 18)],
			["03_door",     Vector3(0, 1.7, 7),    Vector3(0, 1.6, -18)],
			["05_close",    Vector3(2, 1.6, -40),  Vector3(0.3, 1.6, -44.9)],
			["06_houses",   Vector3(-20, 4, -16),  Vector3(-28, 1.5, -24)],
			["07_skyline",  Vector3(0, 3, 6),      Vector3(0, 4, -60)],
			["08_top",      Vector3(0, 52, 0.1),   Vector3(0, 0, 0)],
			["09_flowers",  Vector3(-30, 3.2, -28),Vector3(-32.9, 2.2, -30.5)],
		])
		for v in views:
			cam.global_position = v[1]
			cam.look_at(v[2], Vector3.UP)
			for i in range(10):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img == null: print("SHOT: null ", v[0])
			else:
				img.save_png("%s/%s.png" % [out_dir, v[0]])
				print("SHOT: ", v[0])
	else:
		print("SHOT: no camera")

	get_tree().quit(0)

func _path_of(n: Node, root: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	while cur != null and cur != root:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
	return "/".join(parts)

func _all(root: Node, cls: String) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls): out.append(n)
		for c in n.get_children(): stack.append(c)
	return out

func _camera(n: Node) -> Camera3D:
	if n is Camera3D: return n
	for c in n.get_children():
		var f := _camera(c)
		if f != null: return f
	return null

func _body(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D: return n
	for c in n.get_children():
		var f := _body(c)
		if f != null: return f
	return null
