extends Node

## The corruption escalation.
##
## Watches the ACT door. The moment it finishes rising:
##
##   1. the music switches to "ungood night"
##   2. the volume ramps UP over `escalate_seconds`
##   3. the whole map glitches harder in step with the volume - props jitter
##      further, blink more often, and the glitch lights strobe faster
##
## The point is that the player can feel the volume and the corruption rising
## together, so the map falling apart reads as the music getting louder rather
## than as two unrelated effects.
##
## Attach to a plain Node in the hub scene. It finds the door and the glitch
## zone by name, so nothing else needs wiring.

@export_group("Escalation")
## Seconds from the door rising to full corruption.
##
## Kept short on purpose. At 45s the ramp is linear, so ten seconds after the
## door rises the player is only at 9.7% - jitter has moved 0.22 -> 0.27 and the
## world looks completely unchanged. The escalation reads as "nothing happened".
@export var escalate_seconds := 12.0

## Curve shape. 1.0 is linear; values above 1 make the start SLOW and the end
## violent, so the first seconds stay almost calm and then it comes apart fast.
@export var ramp_exponent := 2.2
## Extra music volume at the end of the ramp, in dB on top of the track's own.
@export var peak_extra_db := 7.0
## Hold the music at full volume for this long before the act pulls them in.
## Seconds over which the post-ramp overshoot develops. After the nominal ramp
## finishes the world keeps getting worse for this long, which is the pressure
## that makes the player choose to walk into the door.
@export var overshoot_seconds := 40.0
## Held for compatibility with older scenes; the ramp no longer stops.
@export var hold_at_peak := 8.0

@export_group("Corruption")
## Prop jitter at the start / end of the ramp, in metres.
@export var jitter_from := 0.18
@export var jitter_to := 1.35
## Prop blink chance at the start / end.
@export_range(0.0, 1.0) var blink_from := 0.25
@export_range(0.0, 1.0) var blink_to := 0.88
## Corruption ticks per second at the start / end.
@export var rate_from := 0.70
@export var rate_to := 0.035
## How often the world flickers to black at the end of the ramp, per second.
@export var world_flicker_rate := 0.0
@export var world_flicker_end_rate := 2.2

@export_group("Wiring")
## Name of the door node in this scene.
@export var door_name := "ActDoor_1"
## Name of the glitch zone node in this scene.
@export var zone_name := "GlitchZone"
## Also brighten the glitch lights as it escalates.
@export var drive_lights := true

signal escalation_finished()

var _door: Node3D
var _zone: Area3D
var _world_env: WorldEnvironment
var _t := 0.0
var _running := false
## Permanent corruption floor raised by blackouts, 0..0.85. Added to the ramp in
## progress(), so the world never fully resets to calm after a blackout.
var _boost := 0.0
var _done := false
var _flicker_accum := 0.0
var _base_env_energy := 0.0


func _ready() -> void:
	_door = get_parent().get_node_or_null(door_name) as Node3D
	_zone = get_parent().get_node_or_null(zone_name) as Area3D
	_world_env = _find_env(get_parent())
	if _world_env != null and _world_env.environment != null:
		_base_env_energy = _world_env.environment.ambient_light_energy
	if _door == null:
		push_warning("CorruptionEscalation: no door named '%s'" % door_name)
		return
	if _door.has_signal("risen"):
		_door.connect("risen", _on_door_risen)


func _on_door_risen() -> void:
	# Silence the approach cue FIRST. It plays the same file as the bed we are
	# about to start, and two copies of the same track flam and partially
	# cancel - which is why the music sounded like silence.
	var pm := get_parent().get_node_or_null("ActDoor_1/ProximityMusic")
	if pm != null and pm.has_method("silence"):
		pm.call("silence")

	Music.play_ungood()
	# the objective becomes "GET OUT", and it starts corrupting
	# find the HUD by scanning - it may be named HubHUD or nested, and a
	# get_node_or_null with one hardcoded name silently did nothing
	for c in get_parent().get_children():
		if c.has_method("glitch_objective"):
			c.call("glitch_objective")
			break
	_running = true
	_t = 0.0


func _process(delta: float) -> void:
	if not _running:
		return

	_t += delta
	_apply(progress(), delta)


## Drive every effect from one `t` (0..1). Called every frame while running, and
## once by `boost()` so a blackout's new floor takes effect immediately even when
## the main ramp has not started (or has already finished).
##
## `delta` is passed in rather than read from a member: the world-flicker
## accumulator needs a real frame time, and `boost()` calls this outside
## `_process` where there is no frame delta. A default of 0.0 means a boost
## applies every value except the flicker accumulator, which is correct - a boost
## should not advance the flicker clock.
func _apply(t: float, delta: float = 0.0) -> void:
	# --- music gets louder in step with the corruption ---
	Music.set_ramp(peak_extra_db * t)

	# --- corruption gets worse ---
	if _zone != null:
		if "jitter" in _zone:
			_zone.set("jitter", lerpf(jitter_from, jitter_to, t))
		if "blink_chance" in _zone:
			_zone.set("blink_chance", lerpf(blink_from, blink_to, t))
		if "idle_interval" in _zone:
			_zone.set("idle_interval", lerpf(rate_from, rate_to, t))
		if "inside_interval" in _zone:
			_zone.set("inside_interval", lerpf(rate_from, rate_to, t) * 0.2)

	# --- glitch lights strobe faster as it builds ---
	# Exclude the door's lights so the player can always find the exit.
	if drive_lights:
		for l in _lights(get_parent()):
			if l.get_script() == null:
				continue
			# Skip any light that is a child of the door
			if _door != null and _door.is_ancestor_of(l):
				continue
			if "steps_per_second" in l:
				l.set("steps_per_second", lerpf(9.0, 70.0, t))
			if "blackout_chance" in l:
				l.set("blackout_chance", lerpf(0.30, 0.95, t))

	# --- the whole world starts flickering out ---
	# Disabled: the black flicker hurts the eyes and looks bad.
	# The glitch is still visible through jitter, blink, and light strobing.
	# if world_flicker_end_rate > 0.0:
	# 	_world_flicker(delta, t)

	# THE RAMP DOES NOT STOP.
	#
	# The player is no longer pulled in - they have to choose to walk through the
	# door. So the pressure has to keep building for as long as they resist.
	# Holding at t=1.0 and stopping would give them a stable, survivable world to
	# stand in, and they would never go in.
	#
	# Past the nominal ramp the effect keeps creeping: the overshoot is applied on
	# top of the peak values, so jitter, blink rate and the music all continue to
	# worsen the longer they wait outside.
	if t >= 1.0 and not _done:
		_done = true
		escalation_finished.emit()


## Drop the world's ambient light for a frame, so the whole scene blinks out.
func _world_flicker(delta: float, t: float) -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var rate := lerpf(world_flicker_rate, world_flicker_end_rate, t)
	if rate <= 0.0:
		return
	_flicker_accum += delta * rate
	if _flicker_accum < 1.0:
		return
	_flicker_accum = 0.0
	var env := _world_env.environment
	env.ambient_light_energy = _base_env_energy * 0.06
	var back := create_tween()
	back.tween_interval(0.045)
	back.tween_property(env, "ambient_light_energy", _base_env_energy, 0.18)


func _find_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n as WorldEnvironment
	for c in n.get_children():
		var f := _find_env(c)
		if f != null:
			return f
	return null


func _lights(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n is OmniLight3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_lights(c))
	return out


## The shaped ramp, 0..1.
##
## Linear over 45s meant the first ten seconds moved the world by almost nothing,
## so the escalation read as "it did not get glitchier". The exponent keeps the
## opening calm and then brings it apart quickly.
func _curve() -> float:
	var lin := clampf(_t / maxf(escalate_seconds, 0.01), 0.0, 1.0)
	return pow(lin, ramp_exponent)


## How far through the escalation we are, 0..1.
##
## `_boost` is a permanent floor added by blackouts: once the player has passed
## out, the world never returns to fully calm, so `progress()` starts from a
## higher baseline each time they wake. This is the "the glitch gets stronger the
## more blackouts you have" ramp.
##
## Past the nominal ramp (`_t > escalate_seconds`) this KEEPS CLIMBING into
## `overshoot`, because the player is not pulled in and has to be worn down. The
## clamp is at 1.6, not 1.0, so there is real headroom above the "peak" values -
## jitter, flicker rate and music all keep worsening while they stand outside.
func progress() -> float:
	var over := 0.0
	if escalate_seconds > 0.0 and _t > escalate_seconds:
		# ~+0.5 over the next `overshoot_seconds`, then very slowly onward
		over = minf((_t - escalate_seconds) / maxf(overshoot_seconds, 0.01), 1.0) * 0.55
	return clampf(_curve() + _boost + over, 0.0, 1.6)


## Raise the permanent corruption floor by `amount`. Called once per blackout.
func boost(amount: float) -> void:
	_boost = clampf(_boost + amount, 0.0, 0.85)
	# apply immediately so the effect is visible the moment they wake
	_apply(_boost)


## The current permanent floor, for tests and readouts.
func boost_level() -> float:
	return _boost


func is_finished() -> bool:
	return _done
