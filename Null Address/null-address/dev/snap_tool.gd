extends Node

## Measures the gap under every prop and writes a machine-readable fix list.
## Headless - measuring needs physics, not a renderer.

@export var out_json := "C:/Users/Santi/AppData/Local/hermes/cache/scratch/fixes.json"

## Structural things, plus fence RAILS: a rail sits between two posts by design
## and is not floating, so a naive gap check flags 18 of them wrongly.
const SKIP := ["Ground", "Ground2", "Boundary", "Skyline", "DoorSlab", "back_wall",
	"back_pillar", "Sign", "ActDoor", "Ceiling", "Wall", "Zone", "Rail",
	# these are children the dead_tree script builds at RUNTIME, not scene
	# nodes - checking a tree's own branches against the ground is meaningless
	"Branch", "Crown", "Blob", "DeadLimb", "Trunk"]

func _ready() -> void:
	await get_tree().process_frame
	for i in range(40):
		await get_tree().process_frame
	for i in range(10):
		await get_tree().physics_frame

	var root := get_parent()
	var space := get_viewport().world_3d.direct_space_state
	var fixes: Array = []

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
		if gap <= 0.07: continue
		if not (hn.begins_with("Ground") or hn.begins_with("Boundary")): continue
		if gap > 1.6: continue

		# record the NODE PATH and the y delta to apply
		fixes.append({
			"path": _path_of(mi, root),
			"node": str(mi.name),
			"delta": -gap,
			"gap": gap,
		})

	var f := FileAccess.open(out_json, FileAccess.WRITE)
	if f == null:
		print("SNAP: cannot write ", out_json)
	else:
		f.store_string(JSON.stringify(fixes, "  "))
		f.close()

	print("SNAP_TOTAL: %d" % fixes.size())
	var by_kind := {}
	for x in fixes:
		var k: String = str(x["path"]).split("/")[-2] if str(x["path"]).count("/") > 1 else str(x["node"])
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	var keys := by_kind.keys()
	keys.sort()
	for k in keys.slice(0, 25):
		print("  %-28s %d" % [k, by_kind[k]])
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
