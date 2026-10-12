extends Node

## Screenshot harness (development only).
##
## Runs the game for a few seconds, captures the viewport from a set of camera
## angles, and writes PNGs to disk so the result can actually be inspected
## instead of assumed. Drop it into a scene temporarily; do not ship it.

@export var output_dir := "C:/Users/Santi/AppData/Local/hermes/cache/scratch/shots"
@export var warmup_frames := 90
@export var settle_frames := 8

# (name, position, look_at_target)
var _shots: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	await get_tree().process_frame
	await _capture_all()
	get_tree().quit(0)


func _capture_all() -> void:
	# Let lighting and the first frames settle.
	for i in warmup_frames:
		await get_tree().process_frame

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		print("SHOT: no camera")
		return

	# Build a survey of the space: spawn view, each corner, upstairs, wide.
	var root := get_parent()
	var views := _plan_views(root)
	print("SHOT: %d views planned" % views.size())

	var body := _find_body(get_parent())

	for v in views:
		var name: String = v[0]
		var pos: Vector3 = v[1]
		var target: Vector3 = v[2]

		# Drive the CharacterBody3D: it owns the camera AND the player light.
		if body != null and is_instance_valid(body):
			body.global_position = pos - Vector3(0, 0.5, 0)
			body.velocity = Vector3.ZERO

		cam.global_position = pos
		if pos.distance_to(target) > 0.01:
			cam.look_at(target, Vector3.UP)

		for i in settle_frames:
			await get_tree().process_frame

		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("SHOT: null image for %s" % name)
			continue
		var path := "%s/%s.png" % [output_dir, name]
		var err := img.save_png(path)
		print("SHOT: %s -> %s (%d)" % [name, path, err])


func _find_body(node: Node) -> CharacterBody3D:
	if node is CharacterBody3D:
		return node
	for c in node.get_children():
		var f := _find_body(c)
		if f != null:
			return f
	return null


func _plan_views(root: Node) -> Array:
	var out: Array = []
	# Spawn view (where the player starts) looking into the room.
	var player := _find_body(root)
	if player != null:
		var p: Vector3 = player.global_position + Vector3(0, 0.6, 0)
		out.append(["01_spawn", p, p + Vector3(0, 0, -8)])
		out.append(["02_spawn_left", p, p + Vector3(-8, 0, 0)])
		out.append(["03_spawn_right", p, p + Vector3(8, 0, 0)])
		out.append(["04_spawn_back", p, p + Vector3(0, 0, 8)])

	# Room corners at eye height, looking at the centre.
	out.append(["05_nw", Vector3(-11, 1.6, -8), Vector3(0, 1.4, 0)])
	out.append(["06_ne", Vector3(11, 1.6, -8), Vector3(0, 1.4, 0)])
	out.append(["07_sw", Vector3(-11, 1.6, 8), Vector3(0, 1.4, 0)])
	out.append(["08_se", Vector3(11, 1.6, 8), Vector3(0, 1.4, 0)])
	# Upstairs
	out.append(["09_up_w", Vector3(-10, 5.0, 0), Vector3(0, 4.6, 0)])
	out.append(["10_up_e", Vector3(10, 5.0, 0), Vector3(0, 4.6, 0)])
	# High wide shot to read the whole layout
	out.append(["11_wide", Vector3(0, 12, 24), Vector3(0, 2, 0)])
	out.append(["12_top", Vector3(0, 22, 0.1), Vector3(0, 0, 0)])
	return out
