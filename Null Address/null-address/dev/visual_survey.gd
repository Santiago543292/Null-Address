extends Node

## Full visual survey of the hub. Renders multiple angles and measures luminance.

@export var out_dir := "C:/Users/Santi/AppData/Local/hermes/cache/scratch/hub_visual"

var fails: Array[String] = []
var passes := 0

func _check(c: bool, l: String) -> void:
	if c: passes += 1; print("  PASS  ", l)
	else: fails.append(l); print("  FAIL  ", l)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame

	var hub_ps: PackedScene = load("res://Maps/HUBsc.tscn")
	var hub := hub_ps.instantiate()
	get_tree().root.add_child(hub)
	for i in range(50):
		await get_tree().process_frame
	for i in range(10):
		await get_tree().physics_frame

	# hide HUD
	var hud := hub.get_node_or_null("HubHUD")
	if hud != null and hud is CanvasLayer:
		(hud as CanvasLayer).visible = false

	var body := _body(hub)
	var cam := _camera(body) if body != null else null
	if cam == null:
		print("SURVEY: no camera found")
		get_tree().quit(1)
		return
	cam.top_level = true

	# get scene bounds
	var meshes := _all(hub, "MeshInstance3D")
	var min_p := Vector3(999, 999, 999)
	var max_p := Vector3(-999, -999, -999)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.top_level or not mi.visible:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		if box.size.x > 80.0 or box.size.z > 80.0 or box.size.y > 60.0:
			continue
		min_p.x = minf(min_p.x, box.position.x)
		min_p.y = minf(min_p.y, box.position.y)
		min_p.z = minf(min_p.z, box.position.z)
		max_p.x = maxf(max_p.x, box.end.x)
		max_p.y = maxf(max_p.y, box.end.y)
		max_p.z = maxf(max_p.z, box.end.z)

	var center := (min_p + max_p) * 0.5
	var extent := (max_p - min_p).length()
	print("SURVEY: scene center=", center, " extent=", extent)
	print("SURVEY: mesh count=", meshes.size())

	# camera views
	var views := [
		["01_wide",    center + Vector3(0, 8, 25),  center],
		["02_street",  center + Vector3(15, 3, 15), center],
		["03_low",     center + Vector3(5, 0.8, 5), center + Vector3(0, 1.5, 0)],
		["04_house",   center + Vector3(-12, 2, -12), center + Vector3(-15, 1, -15)],
		["05_top",     center + Vector3(0, 60, 0.1), center],
		["06_close",   center + Vector3(3, 2, 3), center],
	]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("%s/%s.png" % [out_dir, v[0]])
			# measure luminance
			var lum := 0.0
			var count := 0
			for y in range(0, img.get_height(), 4):
				for x in range(0, img.get_width(), 4):
					var c := img.get_pixel(x, y)
					lum += (c.r + c.g + c.b) / 3.0
					count += 1
			if count > 0:
				lum /= count
			print("  %-12s mean luminance=%.3f" % [v[0], lum])
			_check(lum > 0.08, "%s: mean luminance %.3f (want > 0.08)" % [v[0], lum])
		print("SHOT: ", v[0])

	get_tree().quit(0 if fails.is_empty() else 1)

func _all(root: Node, cls: String) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls): out.append(n)
		for c in n.get_children(): stack.append(c)
	return out

func _camera(n: Node) -> Camera3D:
	if n == null: return null
	if n is Camera3D: return n
	for c in n.get_children():
		var f := _camera(c)
		if f != null: return f
	return null

func _body(n: Node) -> CharacterBody3D:
	if n == null: return null
	if n is CharacterBody3D: return n
	for c in n.get_children():
		var f := _body(c)
		if f != null: return f
	return null
