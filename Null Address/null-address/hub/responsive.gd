extends Node3D

## The house responds to the player.
##
## Two-way feedback that makes the space feel observed without anything being
## in it:
##
##   - the lights nearest the player brighten slightly, so the house leans in
##   - lamps far away dim, so the far end of the house stays unknowable
##   - the tape overlay's noise, aberration and vignette creep up over time
##   - a heartbeat fades in when the player has been still for a long while
##
## All of it is driven by distance and elapsed time only. There is no entity.

@export_group("Light Response")
## How much nearby lights brighten when the player approaches.
@export var approach_boost := 0.45
## How much distant lights dim.
@export var distance_dim := 0.35
@export var near_radius := 5.0
@export var far_radius := 20.0

@export_group("Tape Degradation")
## Seconds before the tape is at its worst.
@export var degrade_seconds := 420.0
@export var max_noise_add := 0.06
@export var max_aberration_add := 0.003
@export var max_vignette_add := 0.18

@export_group("Stillness")
## Seconds of not moving before the heartbeat starts.
@export var still_seconds := 12.0
@export_range(-60.0, 0.0) var heartbeat_db := -22.0

var _camera: Camera3D
var _body: CharacterBody3D
var _lights: Array[OmniLight3D] = []
var _base_energy: Array[float] = []
var _mat: ShaderMaterial
var _base_noise := 0.08
var _base_aberration := 0.0035
var _base_vignette := 0.3

var _elapsed := 0.0
var _still := 0.0
var _heart: AudioStreamPlayer


func _ready() -> void:
	_gather_lights()
	_find_player()
	_find_tape_material()
	_build_heartbeat()


func _gather_lights() -> void:
	var lamps := get_parent().get_node_or_null("Lights") if get_parent() else null
	if lamps == null:
		return
	for fixture in lamps.get_children():
		for c in fixture.get_children():
			if c is OmniLight3D:
				_lights.append(c)
				var raw: Variant = c.get("base_energy")
				_base_energy.append(float(raw) if raw != null else c.light_energy)


func _find_player() -> void:
	_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	if _camera == null:
		return
	var n: Node = _camera
	while n != null:
		if n is CharacterBody3D:
			_body = n as CharacterBody3D
			return
		n = n.get_parent()


func _find_tape_material() -> void:
	# Walk up to the house root, then find the player's tape overlay.
	var root := get_parent()
	if root == null:
		return
	var overlay := root.find_child("TapeOverlay", true, false)
	if overlay == null:
		return
	if overlay is CanvasItem and overlay.material is ShaderMaterial:
		_mat = overlay.material
		var raw: Variant = _mat.get_shader_parameter("static_noise")
		if raw != null:
			_base_noise = float(raw)
		raw = _mat.get_shader_parameter("edge_aberration")
		if raw != null:
			_base_aberration = float(raw)
		raw = _mat.get_shader_parameter("vignette_intensity")
		if raw != null:
			_base_vignette = float(raw)


func _build_heartbeat() -> void:
	_heart = AudioStreamPlayer.new()
	_heart.volume_db = heartbeat_db
	_heart.stream = _make_heartbeat()
	add_child(_heart)


## A two-thump heartbeat, synthesised: 55Hz body plus a click transient.
func _make_heartbeat() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.9)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		# thump 1 at 0.0s, thump 2 at 0.28s
		for k in 2:
			var off := 0.28 * float(k)
			if t >= off:
				var lt := t - off
				var env := exp(-lt * 16.0)
				var amp := 1.0 if k == 0 else 0.72
				v += sin(TAU * 55.0 * lt) * env * amp
				v += (exp(-lt * 220.0)) * 0.25 * amp
		bytes.encode_s16(i * 2, int(clampf(v * 0.9, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_find_player()
	if _camera == null:
		return

	_elapsed += delta

	# --- stillness tracking ---
	if _body != null and is_instance_valid(_body):
		var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
		if speed < 0.4:
			_still += delta
		else:
			_still = 0.0

	if _heart != null:
		var want := _still > still_seconds and not _heart.playing
		if want:
			_heart.play()

	# --- lights lean toward the player ---
	var pp := _camera.global_position
	for i in _lights.size():
		var l := _lights[i]
		if not is_instance_valid(l):
			continue
		var d := l.global_position.distance_to(pp)
		var near := 1.0 - clampf((d - near_radius) / maxf(far_radius - near_radius, 0.01), 0.0, 1.0)
		var factor := lerpf(1.0 - distance_dim, 1.0 + approach_boost, near)
		l.light_energy = _base_energy[i] * factor

	# --- the tape gets worse the longer you are inside ---
	if _mat != null:
		var t: float = clampf(_elapsed / maxf(degrade_seconds, 1.0), 0.0, 1.0)
		_mat.set_shader_parameter("static_noise", _base_noise + max_noise_add * t)
		_mat.set_shader_parameter("edge_aberration", _base_aberration + max_aberration_add * t)
		_mat.set_shader_parameter("vignette_intensity", _base_vignette + max_vignette_add * t)
