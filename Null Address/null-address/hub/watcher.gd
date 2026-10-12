extends Node3D

## THE WATCHER - a presence that makes the player feel observed.
##
## DESIGN: it is never shown. There is no mesh, no model, no visible body. What
## the player experiences is a set of CUES that only make sense if something is
## there:
##
##   * a slow breath behind them, panned to their left or right, fading in
##   * footsteps that stop when they stop
##   * the lamp nearest them dimming as it passes
##   * a shape in the corner of the frame that is gone when they turn to look
##
## Every cue is gated on being UNOBSERVED (see `_unseen`). The player learns the
## pattern - it only happens when I am not looking - and that is what converts
## "random ambience" into "something is avoiding me".
##
## ESCALATION: it gets bolder with each blackout. Early on it keeps its distance
## and only breathes. Later it closes in, touches the lamps, and the cues overlap.
##
## It deliberately has NO collision and NO way to catch the player. The threat is
## entirely in the player's head, which is more effective than any model and
## costs nothing to ship. DO NOT add a visible body to this - see the note at the
## bottom of this file.
##
## Attach to a plain Node3D in the hub scene.

@export_group("Presence")
## How far from the player it can be when it makes a sound, in metres.
@export var near_distance := 3.0
@export var far_distance := 9.0
## Seconds between cues at the start.
@export var cue_min_gap := 11.0
@export var cue_max_gap := 22.0
## Grace before the first cue, so the player settles first.
@export var grace_seconds := 14.0
## Never place a cue within this of the player - it must not feel like a jump
## scare. The player should never be able to pin it to a spot.
@export var min_spawn_distance := 4.0

@export_group("Escalation")
## Each blackout shortens the gap and closes the distance. This is the "it gets
## bolder the more you black out" ramp.
@export var gap_shrink_per_blackout := 0.78
@export var distance_shrink_per_blackout := 0.85
## Past this many blackouts it starts interfering with the lamps directly.
@export var touch_lamps_after := 2

@export_group("Lure")
## Name of the act door. Once it is UP the watcher stops being neutral ambience
## and starts herding: cues land on the side away from the door so the player is
## pushed toward it rather than chased.
@export var door_name := "ActDoor_1"
## How much more often it acts once the door is up. The field should feel worse
## than the way in.
@export var lure_gap_multiplier := 0.65
## How long after a cue we keep checking whether the player turned to look at it.
## If they do, the sound cuts dead. This is the "it knows you looked" beat.
@export var look_watch_seconds := 2.5

@export_group("Audio")
## Base volume of a cue, in dB. Deliberately quiet - it should be deniable.
@export var cue_volume_db := -16.0
## Extra dB per blackout.
@export var volume_growth_db := 2.0

signal cue_made(kind: String)
## Emitted when the player turns to look at where a cue came from and it stops.
signal caught_looking()

var _player: CharacterBody3D
var _camera: Camera3D
var _lamps: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _blackouts := 0
## Where the last cue came from, and how long we keep checking whether the player
## has turned to look at it.
var _last_spot := Vector3.ZERO
var _look_watch := 0.0
var _breath: AudioStreamPlayer3D
var _steps: AudioStreamPlayer3D
var _playing := false
var _hiding: Node


func _ready() -> void:
	_rng.randomize()
	_player = _find_player()
	_camera = get_viewport().get_camera_3d()
	_adopt_lamps()
	_build_audio()
	_build_visible_form()
	_hiding = _find_hiding()
	_timer = grace_seconds
	_watch_blackouts()
	# The monster is always visible and drifts around the map so the player
	# can see it the whole time, not just during cues.
	if always_visible:
		_visible_form.visible = true
		_visible_t = 999999.0
		global_position = _pick_spot()
		_visible_form.look_at(_player.global_position, Vector3.UP)


## Follow the puzzle's blackout count so it can escalate with it.
func _watch_blackouts() -> void:
	for c in get_parent().get_children():
		if c.has_method("pass_lamp_count") or c.name == "LampPuzzle":
			if c.has_signal("passed_out"):
				c.connect("passed_out", _on_passed_out)
			return


func _on_passed_out() -> void:
	_blackouts += 1
	# it gets closer and more frequent
	_timer = minf(_timer, _current_gap() * 0.4)


func _adopt_lamps() -> void:
	var holder := get_parent().get_node_or_null("LampPosts")
	if holder == null:
		return
	for c in holder.get_children():
		if c is Node3D:
			_lamps.append(c)


## Procedural audio, so there is no file to ship and every cue can be varied.
func _build_audio() -> void:
	_breath = AudioStreamPlayer3D.new()
	_breath.name = "Breath"
	_breath.stream = _make_breath()
	_breath.volume_db = cue_volume_db
	_breath.max_distance = 24.0
	_breath.unit_size = 6.0
	_breath.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_breath)

	_steps = AudioStreamPlayer3D.new()
	_steps.name = "Steps"
	_steps.stream = _make_steps()
	_steps.volume_db = cue_volume_db
	_steps.max_distance = 24.0
	_steps.unit_size = 6.0
	_steps.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_steps)


## Is `pos` out of the player's view? The whole effect rests on this.
func _unseen(pos: Vector3) -> bool:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return true        # no camera to judge by - allow the cue
	return not _camera.is_position_in_frustum(pos)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return

	# HIDING. If the player is inside a hiding spot the watcher does not find
	# them: no cues at all. This is what makes hiding a real mechanic rather than
	# a pose - without this check the monster keeps breathing down your neck
	# inside a wardrobe and the player learns hiding does nothing.
	# While hidden it stays quiet AND does not look for them.
	if _hiding != null and is_instance_valid(_hiding) and _hiding.has_method("is_hidden"):
		if bool(_hiding.call("is_hidden")):
			# it waits, but does not act. Reset the timer so the first cue after
			# they come out is a full gap away rather than instant.
			_timer = maxf(_timer, _current_gap() * 0.5)
			_look_watch = 0.0
			return

	# Did the player turn to look at where the last cue came from? If so it goes
	# silent. Runs before the timer so a cue can be cut short mid-play.
	_check_caught_looking(delta)

	# Tick the visible form
	if _visible_t > 0.0:
		_visible_t -= delta
		if _visible_t <= 0.0:
			_hide_visible_form()

	# When always_visible is on, the monster drifts around the player so it
	# is always on screen and always moving.
	if always_visible and _player != null and is_instance_valid(_player):
		var target := _pick_spot()
		global_position = global_position.move_toward(target, delta * 2.0)
		_visible_form.look_at(_player.global_position, Vector3.UP)

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _current_gap()
	_make_cue()


## Find the hub's hiding registry by capability, not by name.
func _find_hiding() -> Node:
	var root := get_parent()
	if root == null:
		return null
	for c in root.get_children():
		if c.has_method("is_hidden") and c.has_method("register"):
			return c
	return null


## Seconds until the next cue, shrinking with each blackout - and further
## shrinking once the door is up, because the field has to feel worse than the
## way in or the player has no reason to walk through it.
func _current_gap() -> float:
	var shrink := pow(gap_shrink_per_blackout, float(_blackouts))
	if _door_position() != null:
		shrink *= lure_gap_multiplier
	return _rng.randf_range(cue_min_gap, cue_max_gap) * shrink


## How close it dares to come, closing in with each blackout.
func _current_distance() -> float:
	var shrink := pow(distance_shrink_per_blackout, float(_blackouts))
	var far := maxf(far_distance * shrink, min_spawn_distance)
	return _rng.randf_range(near_distance, far)


## Pick somewhere behind/beside the player that they are NOT looking at.
##
## WHEN THE DOOR IS UP, this is biased so the cue lands on the side AWAY from the
## door. Standing between the player and the exit and breathing makes them back
## away from it - toward the door. The watcher becomes a shepherd: it does not
## chase the player in, it makes the rest of the field feel worse than the way in.
func _pick_spot() -> Vector3:
	var pp := _player.global_position
	# explicit Variant: _door_position() can return null, and `:=` on a Variant
	# return is a hard error under this project's warning-as-error settings
	var door_pos: Variant = _door_position()

	for attempt in 16:
		var yaw := _rng.randf_range(0.0, TAU)
		var d := _current_distance()
		var pos := pp + Vector3(cos(yaw), 0.0, sin(yaw)) * d
		pos.y = pp.y + _rng.randf_range(-0.4, 1.2)
		if not _unseen(pos):
			continue
		# once the door is up, prefer spots that push the player toward it
		if door_pos != null:
			var to_door: Vector3 = (door_pos as Vector3) - pp
			var to_spot: Vector3 = pos - pp
			if to_door.length() > 0.5 and to_spot.length() > 0.5:
				var toward := to_door.normalized().dot(to_spot.normalized())
				# >0 means the cue is on the door's side. Reject those most of the
				# time so the pressure comes from everywhere EXCEPT the exit.
				if toward > 0.25 and _rng.randf() < 0.8:
					continue
		return pos

	# nothing suitable - fall back to directly opposite the door
	if door_pos != null:
		var away: Vector3 = pp - (door_pos as Vector3)
		if away.length() > 0.5:
			return pp + away.normalized() * _current_distance() + Vector3(0, 0.4, 0)
	var back := -_player.global_transform.basis.z
	return pp + back * _current_distance() + Vector3(0, 0.4, 0)


## The act door's position, or null if there is none / it is not up yet.
func _door_position() -> Variant:
	var d := get_parent().get_node_or_null(door_name)
	if d == null or not (d is Node3D):
		return null
	if d.has_method("is_risen") and not bool(d.call("is_risen")):
		return null
	return (d as Node3D).global_position


func _make_cue() -> void:
	var pos := _pick_spot()
	global_position = pos
	# remember where it "is" so we can tell if the player turns to look at it
	_last_spot = pos
	_look_watch = look_watch_seconds

	# pick a cue. Breathing early; it starts touching things later.
	var roll := _rng.randf()
	var kind := "breath"
	if _blackouts >= touch_lamps_after and roll < 0.45:
		kind = "lamp"
	elif roll < 0.35:
		kind = "steps"

	match kind:
		"breath":
			_play_breath()
		"steps":
			_play_steps()
		"lamp":
			_dim_a_lamp()
	_show_visible_form()
	cue_made.emit(kind)


## THE BEAT THAT MAKES IT FEEL WATCHED.
##
## For a moment after a cue, if the player turns and puts that spot in view, the
## sound STOPS - dead silence, immediately. Nothing is there. The player learns
## that looking at it is what makes it go quiet, which is far more unsettling
## than anything that stays on screen: they are now the reason it vanished.
##
## This runs alongside the normal cue timer, so it can cut a cue short.
func _check_caught_looking(delta: float) -> void:
	if _look_watch <= 0.0:
		return
	_look_watch -= delta
	if _camera == null or not is_instance_valid(_camera):
		return
	if not _camera.is_position_in_frustum(_last_spot):
		return

	# they are looking right at where it was. Cut everything.
	_look_watch = 0.0
	if _breath != null and _breath.playing:
		_breath.stop()
	if _steps != null and _steps.playing:
		_steps.stop()
	caught_looking.emit()
	# and it stays away for a while - it does not want to be found
	_timer = maxf(_timer, _current_gap() * 1.4)


func _play_breath() -> void:
	if _breath == null:
		return
	_breath.volume_db = cue_volume_db + volume_growth_db * float(_blackouts)
	_breath.pitch_scale = _rng.randf_range(0.82, 0.94)   # pitched down: wrong
	_breath.play()
	_fade_out(_breath, 2.2)


func _play_steps() -> void:
	if _steps == null:
		return
	_steps.volume_db = cue_volume_db + volume_growth_db * float(_blackouts)
	_steps.pitch_scale = _rng.randf_range(0.84, 0.96)
	_steps.play()
	_fade_out(_steps, 1.6)


## Duck a nearby lamp as if something passed in front of it.
func _dim_a_lamp() -> void:
	if _lamps.is_empty():
		return
	var best: Node3D = null
	var best_d := INF
	for l in _lamps:
		if not is_instance_valid(l):
			continue
		var d := l.global_position.distance_to(_player.global_position)
		# only lamps the player can see, so they notice it happen
		if d < best_d and _camera != null and _camera.is_position_in_frustum(l.global_position):
			best_d = d
			best = l
	if best == null:
		return
	var light := best.get_node_or_null("Light") as OmniLight3D
	if light == null:
		return
	var base := light.light_energy
	var t := create_tween()
	t.tween_property(light, "light_energy", base * 0.15, 0.35)
	t.tween_interval(0.5)
	t.tween_property(light, "light_energy", base, 0.9)


func _fade_out(p: AudioStreamPlayer3D, seconds: float) -> void:
	var t := create_tween()
	t.tween_interval(maxf(0.1, seconds - 0.4))
	t.tween_property(p, "volume_db", -60.0, 0.4)


# --------------------------------------------------------------- procedural SFX
const RATE := 22050


## A slow breath: low-passed noise with a slow amplitude swell. The least
## information that still reads as something alive.
func _make_breath() -> AudioStreamWAV:
	var dur := 1.9
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in n:
		var t := float(i) / float(n)
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.045)          # heavy low-pass = breath not hiss
		var env := sin(PI * t)                 # in and out
		# two-phase: inhale sharper than exhale
		env *= 0.7 + 0.3 * (1.0 - t)
		s[i] = lp * env
	return _wav(s)


## Footsteps: filtered noise bursts with a low body tone, so they read as weight
## rather than clicks. Several steps, slowing, as if it stops and waits.
func _make_steps() -> AudioStreamWAV:
	var dur := 1.8
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# step onsets, drifting apart (it slows, then stops)
	var onsets := [0.05, 0.44, 0.86, 1.34]
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for o in onsets:
			var dt := t - float(o)
			if dt < 0.0 or dt > 0.3:
				continue
			var noise := rng.randf_range(-1.0, 1.0)
			var body := sin(TAU * 74.0 * dt)
			v += (noise * 0.35 + body * 0.65) * exp(-dt * 24.0)
		s[i] = v * 0.8
	return _wav(s)


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _find_player() -> CharacterBody3D:
	return _body(get_parent())


func _body(n: Node) -> CharacterBody3D:
	if n == null:
		return null
	if n is CharacterBody3D:
		return n
	for c in n.get_children():
		var f := _body(c)
		if f != null:
			return f
	return null


# ---------------------------------------------------------------------------
# VISIBLE FORM
#
# The user asked for a visible monster. This is a compromise: a dark, humanoid
# shape that flickers into existence for ~0.4s during a cue, then vanishes.
# It is never present for long enough to study, and it is always gone by the
# time the player turns to look. The horror comes from the brief glimpse, not
# from a model that stands around.
# ---------------------------------------------------------------------------

var _visible_form: Node3D
var _visible_t := 0.0
var _visible_duration := 0.4
## Whether the monster is always visible (for demo/testing)
@export var always_visible := false

func _build_visible_form() -> void:
	# The VisibleForm node and its children already exist in the scene file
	# (hub/watcher_form.tscn is instanced by HUBsc.tscn). Don't rebuild them —
	# just grab the reference so the script can drive visibility and position.
	_visible_form = get_node_or_null("VisibleForm")
	if _visible_form == null:
		return

	# A tall, gaunt, humanoid figure — not a box. Long limbs, hunched shoulders,
	# a head that is slightly too large, and eyes that glow in the dark.
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.015, 0.015, 0.02)
	skin.metallic = 0.0
	skin.roughness = 0.9
	skin.emission_enabled = true
	skin.emission = Color(0.008, 0.0, 0.0)
	skin.emission_energy_multiplier = 0.2

	# Torso — a tall, thin capsule, slightly hunched
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.22
	torso_mesh.height = 1.6
	torso_mesh.radial_segments = 10
	torso_mesh.rings = 6
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 1.3, 0)
	torso.rotation = Vector3(deg_to_rad(8), 0, 0)  # slight hunch
	torso.material_override = skin
	_visible_form.add_child(torso)

	# Shoulders — two small spheres
	for side in [-1, 1]:
		var sh_mesh := SphereMesh.new()
		sh_mesh.radius = 0.12
		sh_mesh.height = 0.24
		sh_mesh.radial_segments = 6
		sh_mesh.rings = 4
		var sh := MeshInstance3D.new()
		sh.name = "Shoulder" + str(side)
		sh.mesh = sh_mesh
		sh.position = Vector3(side * 0.28, 1.85, 0)
		sh.material_override = skin
		_visible_form.add_child(sh)

	# Head — slightly too large, tilted
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.18
	head_mesh.height = 0.36
	head_mesh.radial_segments = 10
	head_mesh.rings = 6
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = head_mesh
	head.position = Vector3(0, 2.15, 0.05)
	head.rotation = Vector3(deg_to_rad(12), 0, deg_to_rad(5))
	head.material_override = skin
	_visible_form.add_child(head)

	# Eyes — two small, bright red points
	for side in [-1, 1]:
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye_mesh.radial_segments = 6
		eye_mesh.rings = 4
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.9, 0.0, 0.0)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(1.0, 0.0, 0.0)
		eye_mat.emission_energy_multiplier = 4.0
		var eye := MeshInstance3D.new()
		eye.name = "Eye" + str(side)
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.07, 2.18, 0.16)
		eye.material_override = eye_mat
		_visible_form.add_child(eye)

	# Arms — long, thin, hanging down
	for side in [-1, 1]:
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.06
		arm_mesh.height = 1.2
		arm_mesh.radial_segments = 6
		arm_mesh.rings = 4
		var arm := MeshInstance3D.new()
		arm.name = "Arm" + str(side)
		arm.mesh = arm_mesh
		arm.position = Vector3(side * 0.35, 1.2, 0)
		arm.rotation = Vector3(deg_to_rad(5), 0, deg_to_rad(side * 8))
		arm.material_override = skin
		_visible_form.add_child(arm)

	# Legs — long, thin
	for side in [-1, 1]:
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.07
		leg_mesh.height = 1.0
		leg_mesh.radial_segments = 6
		leg_mesh.rings = 4
		var leg := MeshInstance3D.new()
		leg.name = "Leg" + str(side)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.12, 0.5, 0)
		leg.material_override = skin
		_visible_form.add_child(leg)

func _show_visible_form() -> void:
	if _visible_form == null:
		return
	_visible_form.visible = true
	# When always_visible is set, keep it on screen indefinitely (for demo
	# and for the user to see and judge the layout). Otherwise the brief
	# glimpse is the whole effect.
	_visible_t = 999999.0 if always_visible else _visible_duration
	# Face the player
	if _player != null:
		_visible_form.look_at(_player.global_position, Vector3.UP)

func _hide_visible_form() -> void:
	if _visible_form != null:
		_visible_form.visible = false
