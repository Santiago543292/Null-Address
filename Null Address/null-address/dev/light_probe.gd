extends Node
## Prints the average brightness of the rendered frame and the state of the
## things that control it. Headless cannot render, so this runs windowed.

@export var out_png := "C:/Users/Santi/AppData/Local/hermes/cache/scratch/probe.png"

func _ready() -> void:
	await get_tree().process_frame
	for i in range(80):
		await get_tree().process_frame
	for i in range(10):
		await get_tree().physics_frame

	var root := get_parent()
	var hud := root.get_node_or_null("HubHUD")
	if hud != null and hud is CanvasLayer:
		(hud as CanvasLayer).visible = false

	print("=== LIGHT PROBE ===")
	var env := get_viewport().world_3d.environment
	if env == null:
		print("  world environment: NONE")
	else:
		print("  ambient_energy : %.2f" % env.ambient_light_energy)
		print("  ambient_color  : %s" % str(env.ambient_light_color))
		print("  tonemap_exposure: %.2f" % env.tonemap_exposure)
		print("  fog_density    : %.3f" % env.fog_density)
		print("  bg_mode        : %d" % env.background_mode)

	var moon := root.get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		print("  moon energy    : %.2f  color %s" % [moon.light_energy, str(moon.light_color)])

	# count the lights that actually exist
	var lights := _all(root, "OmniLight3D")
	print("  omni lights    : %d" % lights.size())
	var on := 0
	for l in lights:
		if (l as OmniLight3D).visible and (l as OmniLight3D).light_energy > 0.1: on += 1
	print("  lit omnis      : %d" % on)

	# the ground material
	var ground := root.get_node_or_null("Ground")
	if ground != null:
		print("  Ground node    : %s (%s)" % [ground.get_class(), ground.name])
		var gi := ground as MeshInstance3D
		if gi != null and gi.mesh != null and gi.mesh.get_surface_count() > 0:
			var m := gi.get_surface_override_material(0)
			if m == null: m = gi.mesh.surface_get_material(0)
			var bm := m as BaseMaterial3D
			if bm != null:
				print("  ground albedo  : %s" % str(bm.albedo_color))
				print("  ground texture : %s" % ("yes" if bm.albedo_texture != null else "NONE"))
	else:
		print("  Ground node    : not found at root")

	# render one frame and measure its brightness
	var body := _body(root)
	var cam := _camera(body) if body != null else null
	if cam != null:
		cam.top_level = true
		cam.global_position = Vector3(5, 1.6, 12)
		cam.look_at(Vector3(10, 0.5, 20), Vector3.UP)
		for i in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(out_png)
			var total := 0.0
			var n := 0
			var brightest := 0.0
			for y in range(0, img.get_height(), 4):
				for x in range(0, img.get_width(), 4):
					var c := img.get_pixel(x, y)
					var lum := (c.r + c.g + c.b) / 3.0
					total += lum
					n += 1
					if lum > brightest: brightest = lum
			print("  frame mean lum : %.4f  (0=black 1=white)" % (total / max(1, n)))
			print("  frame max lum  : %.4f" % brightest)
	get_tree().quit(0)

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
