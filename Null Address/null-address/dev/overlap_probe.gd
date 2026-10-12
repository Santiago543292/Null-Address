extends Node

## Detects objects whose AABBs overlap (stuff inside itself).
## Reports overlapping pairs and suggests fixes.

var fails: Array[String] = []
var passes := 0
var _overlaps: Array[String] = []

func _check(c: bool, l: String) -> void:
	if c: passes += 1; print("  PASS  ", l)
	else: fails.append(l); print("  FAIL  ", l)

func _ready() -> void:
	await get_tree().process_frame
	print("=== OVERLAP DETECTION ===")

	var hub_ps: PackedScene = load("res://Maps/HUBsc.tscn")
	var hub := hub_ps.instantiate()
	get_tree().root.add_child(hub)
	for i in range(50):
		await get_tree().process_frame
	for i in range(10):
		await get_tree().physics_frame

	# Collect all MeshInstance3D nodes with their world AABBs
	var meshes: Array[Node3D] = []
	var aabbs: Array[AABB] = []
	for m in _all(hub, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.top_level or not mi.visible:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		# Skip enormous ground/boundary meshes
		if box.size.x > 80.0 or box.size.z > 80.0 or box.size.y > 60.0:
			continue
		meshes.append(mi)
		aabbs.append(box)

	print("  Checking %d meshes for overlaps..." % meshes.size())

	# Check all pairs for AABB overlap
	var overlap_count := 0
	for i in range(meshes.size()):
		for j in range(i + 1, meshes.size()):
			if aabbs[i].intersects(aabbs[j]):
				overlap_count += 1
				var name_a: String = meshes[i].name
				var name_b: String = meshes[j].name
				var pos_a: Vector3 = (meshes[i] as Node3D).global_position
				var pos_b: Vector3 = (meshes[j] as Node3D).global_position
				var dist := pos_a.distance_to(pos_b)
				_overlaps.append("%s <-> %s (dist %.1f)" % [name_a, name_b, dist])
				if overlap_count <= 30:
					print("  OVERLAP: %s <-> %s (dist %.1f)" % [name_a, name_b, dist])

	print("  Total overlaps: %d" % overlap_count)
	_check(overlap_count == 0, "%d overlapping objects (want 0)" % overlap_count)

	# Also check for floating objects (above ground or sunk)
	var floating: Array[String] = []
	var sunk: Array[String] = []
	for i in range(meshes.size()):
		var mi: Node3D = meshes[i]
		var bottom: float = aabbs[i].position.y
		var label := "%s (%.1f,%.1f) bottom=%.2f" % [mi.name, mi.global_position.x, mi.global_position.z, bottom]
		if bottom > 0.3:
			floating.append(label)
		elif aabbs[i].end.y < -0.05:
			sunk.append(label)

	print("  Floating objects: %d" % floating.size())
	for f in floating.slice(0, 15):
		print("    ^ %s" % f)
	print("  Sunk objects: %d" % sunk.size())
	for s in sunk.slice(0, 15):
		print("    v %s" % s)

	# Check for objects inside houses
	var houses := hub.get_node_or_null("Houses")
	if houses != null:
		var inside_house: Array[String] = []
		for c in houses.get_children():
			if c is Node3D:
				var house_pos: Vector3 = (c as Node3D).global_position
				for i in range(meshes.size()):
					if meshes[i] == c:
						continue
					var mesh_pos: Vector3 = meshes[i].global_position
					if house_pos.distance_to(mesh_pos) < 8.0:
						var mesh_name: String = meshes[i].name
						# Only report non-house meshes inside houses
						if not mesh_name.begins_with("House") and not mesh_name.begins_with("Furn"):
							inside_house.append("%s inside %s" % [mesh_name, c.name])
		print("  Objects inside houses: %d" % inside_house.size())
		for h in inside_house.slice(0, 15):
			print("    ! %s" % h)

	hub.queue_free()
	await get_tree().process_frame
	_finish()

func _all(root: Node, cls: String) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls): out.append(n)
		for c in n.get_children(): stack.append(c)
	return out

func _finish() -> void:
	print("=== %d passed, %d failed ===" % [passes, fails.size()])
	for f in fails: print("  !! ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
