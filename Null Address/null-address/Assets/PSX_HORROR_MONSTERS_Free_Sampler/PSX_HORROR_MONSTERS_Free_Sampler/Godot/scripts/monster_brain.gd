@tool
class_name MonsterBrain
extends CharacterBody3D
## Enemy behaviour of the PSX Horror Monsters pack (bitkiln - https://bitkiln.itch.io).
##
## Put this script on a CharacterBody3D that has a collision shape and the monster model (any scene with an
## AnimationPlayer, for example one of the pack's GLB files) as children. Every monster scene of the pack
## (res://monsters/<name>/<name>.tscn) is set up like that and already uses it.
##
## States
##   IDLE    stands still (Idle clip), sometimes plays one of idle_variations, then starts to wander
##           (with start_dormant it waits frozen in the first frame of anim_wake until something wakes it)
##   WANDER  strolls to a random point near its start position (Walk clip)
##   CHASE   runs at the target (Run clip, or Walk when use_run is off); plays anim_alert once when it spots one
##   ATTACK  plays Attack or Attack2 (picked at random when both reach); the blow lands attack_hit_time seconds
##           into the clip, but only if the target is still within reach and in front of the monster
##   HIT     plays Hit after damage (a new hit restarts it and cancels an attack), then hunts the attacker
##   DEAD    plays Death once, stops blocking players, monsters and bullets, emits died
##
## Targets are the nodes in target_group ("player" by default). A target may have the methods
## take_damage(amount: float, from_position: Vector3) and is_dead() -> bool; both are optional.
##
## The models face +Z (the glTF convention), so the brain turns the body until +Z points where it goes.
## With a NavigationAgent3D child and a navigation mesh in the level the monster follows paths around walls;
## without them it heads straight for its goal and slides along whatever is in the way.
## Animation names are the pack's (Idle, Walk, Run, Attack, Attack2, Hit, Death); change them in the
## Animations group to use the script with your own models.

## Emitted on every state change (values of State).
signal state_changed(new_state: int, old_state: int)
## A target was noticed (seen, or it hurt the monster).
signal target_spotted(new_target: Node3D)
## The monster gave up the chase (target too far, out of sight for forget_time, or dead).
signal target_lost
## An attack clip started (Attack or Attack2).
signal attack_started(animation: StringName)
## A blow landed on the target (the target's take_damage() was called).
signal attack_landed(victim: Node, amount: float)
## The monster took damage (health_left is the health after it).
signal damaged(amount: float, health_left: float)
## Health reached 0; the Death clip is playing.
signal died

enum State { IDLE, WANDER, CHASE, ATTACK, HIT, DEAD }

## Name shown by the demo scenes.
@export var monster_name := ""
## Off: the monster stands still and ignores targets and damage (the showcase drives the clips itself).
@export var active := true

@export_group("Target")
## Group of the nodes this monster hunts. The demo player adds itself to "player".
@export var target_group: StringName = &"player"
## A target closer than this (metres) is noticed.
@export var detect_range := 12.0
## The chase ends when the target gets farther away than this.
@export var lose_range := 20.0
## Only notice targets that are not hidden behind walls. Damage always wakes the monster up.
@export var need_line_of_sight := true
## Physics layers that block the view (and that the monster keeps standing on when it is dead).
@export_flags_3d_physics var sight_mask := 1
## Height of the eyes above the origin, for the line of sight.
@export var eye_height := 1.5
## Seconds the monster keeps hunting a target it can no longer see.
@export var forget_time := 6.0

@export_group("Movement")
## Speed while wandering, in metres per second.
@export var walk_speed := 0.8
## Speed while chasing.
@export var run_speed := 2.0
## Chase with run_speed and the Run clip. Off: chase at walk_speed with the Walk clip.
@export var use_run := true
## How quickly the speed changes (higher = snappier).
@export var acceleration := 8.0
## Turning speed in degrees per second.
@export var turn_speed := 300.0
## Gravity in metres per second squared (0 = never falls).
@export var gravity := 9.8
## Speed (m/s) at which the feet of the Walk clip move. When set, the Walk clip plays faster or slower to
## match the real speed, so the feet do not slide when you change walk_speed. 0 = always normal speed.
@export var walk_animation_speed := 0.0
## The same for the Run clip.
@export var run_animation_speed := 0.0

@export_group("Wander")
## Stroll around the start position when no target is around.
@export var wander := true
## How far from the start position the monster strolls (metres).
@export var wander_radius := 5.0
## Seconds of standing between two strolls (random between x and y).
@export var idle_time := Vector2(2.0, 5.0)

@export_group("Attack")
## Distance (metres, measured on the floor between the origins) at which the Attack clip starts.
@export var attack_range := 1.2
## Seconds into the Attack clip when the blow lands.
@export var attack_hit_time := 0.5
## Distance at which Attack2 starts (0 = the same as attack_range). A longer range suits leaps and charges.
@export var attack2_range := 0.0
## Seconds into the Attack2 clip when the blow lands.
@export var attack2_hit_time := 0.5
## Chance to pick Attack2 when both attacks can reach.
@export_range(0.0, 1.0) var attack2_chance := 0.4
## Seconds between the end of an attack and the next one.
@export var attack_cooldown := 0.8
## Damage of one blow.
@export var damage := 10.0
## Extra reach when the blow lands: it hits if the target is closer than the attack range plus this.
@export var hit_reach := 0.5
## The blow only hits a target within this angle (degrees) left or right of the monster's front.
@export var hit_angle := 75.0

@export_group("Health")
@export var max_health := 100.0
## Damage plays the Hit clip, which interrupts attacks.
@export var flinch := true
## Minimum seconds between two Hit reactions (the damage of every hit still counts).
@export var flinch_cooldown := 0.35
## Seconds after death before the body is removed from the scene (0 = it stays).
@export var remove_after := 0.0

@export_group("Animations")
## The AnimationPlayer of the model (found on its own when empty).
@export var animation_player: AnimationPlayer
@export var anim_idle: StringName = &"Idle"
@export var anim_walk: StringName = &"Walk"
@export var anim_run: StringName = &"Run"
@export var anim_attack: StringName = &"Attack"
## Second attack, used when the model has it (leave empty for none).
@export var anim_attack2: StringName = &"Attack2"
@export var anim_hit: StringName = &"Hit"
@export var anim_death: StringName = &"Death"
## Played once when the monster spots a target (Scream, Howl...). Empty: none.
@export var anim_alert: StringName = &""
## Start frozen in the first frame of anim_wake (a scarecrow nailed to its cross, a body on the floor...) and come
## alive with that clip when a target is noticed or the monster gets hurt.
@export var start_dormant := false
## The clip of a dormant monster coming alive (e.g. Awaken).
@export var anim_wake: StringName = &""
## Clips played now and then while standing idle.
@export var idle_variations: PackedStringArray = PackedStringArray()
## Clips that loop. Their loop mode is set when the monster starts (the others play once).
@export var loop_animations: PackedStringArray = PackedStringArray(["Idle", "Walk", "Run"])
## Cross-fade time between clips in seconds.
@export var blend_time := 0.2

@export_group("Skin")
## Skin name -> albedo texture of the model (the pack's monster scenes list their skins here).
@export var skin_textures: Dictionary = {}:
	set(value):
		skin_textures = value
		notify_property_list_changed()
		_apply_skin_when_ready()
## The skin to show: one of the names in skin_textures. Empty = the texture inside the model.
@export var skin := "":
	set(value):
		skin = value
		_apply_skin_when_ready()

@export_group("Hover")
## Floating monsters: the model floats this many metres above the floor while alive and sinks down on death.
@export var hover_height := 0.0
## Up and down bob of a floating model in metres.
@export var hover_bob := 0.06
## Seconds for one bob.
@export var hover_period := 2.4
## The node that floats (default: the model, the child that holds the AnimationPlayer).
@export var model: Node3D

@export_group("Navigation")
## Follow the paths of a NavigationAgent3D child when the level has a navigation mesh.
@export var use_navigation := true

## Current state (read only, use the methods to change it).
var state: State = State.IDLE
var health := 100.0
## The node being hunted (null when there is none).
var target: Node3D = null
## Where the monster started; wandering stays around it.
var home := Vector3.ZERO

const PSX_META := &"psx_original_surface_materials"   # set by shaders/apply_psx.gd while the PSX shader is on
static var _skin_cache := {}

var _ap: AnimationPlayer = null
var _nav: NavigationAgent3D = null
var _t := 0.0                     # seconds in the current state
var _clock := 0.0
var _want := Vector3.ZERO         # wanted horizontal velocity
var _face := Vector3.ZERO         # wanted facing direction (flat)
var _cooldown := 0.0
var _flinch_wait := 0.0
var _sense_wait := 0.0
var _unseen := 0.0
var _alert_left := 0.0
var _alert_wait := 0.0
var _dormant := false
var _variation_left := 0.0
var _idle_for := 2.0
var _goal := Vector3.ZERO
var _stuck := 0.0
var _attack_anim: StringName = &""
var _attack_hit := 0.0
var _attack_len := 0.0
var _attack_reach := 0.0
var _attack_done := false
var _hit_len := 0.0
var _model_y := 0.0
var _hover_now := 0.0
var _alive_layer := 0
var _alive_mask := 0
var _nav_check := 0.0
var _nav_ok := false


func _ready() -> void:
	_ap = _find_animation_player()
	if model == null and _ap != null and _ap.get_parent() is Node3D and _ap.get_parent() != self:
		model = _ap.get_parent() as Node3D
	if Engine.is_editor_hint():
		set_physics_process(false)
		_apply_skin()
		return
	health = max_health
	home = global_position
	_alive_layer = collision_layer
	_alive_mask = collision_mask
	_nav = _find_navigation_agent()
	if model != null:
		_model_y = model.position.y
	_hover_now = hover_height
	_sense_wait = randf() * 0.2
	_idle_for = randf_range(idle_time.x, idle_time.y)
	add_to_group(&"monsters")
	_setup_animations()
	_apply_skin()
	if active and start_dormant and has_animation(anim_wake):
		_dormant = true
		play_animation(anim_wake, true, 0.0)
		_ap.pause()                                        # holds the first frame until it wakes up
		return
	play_animation(anim_idle, true, 0.0)
	if _ap != null and _ap.has_animation(anim_idle):
		_ap.seek(randf() * _length(anim_idle), true)      # monsters of one kind do not breathe in sync


func _validate_property(property: Dictionary) -> void:
	if property.name == "skin" and not skin_textures.is_empty():
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(skin_names())


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _find_animation_player() == null:
		warnings.append("No AnimationPlayer found: add the monster model (a scene with an AnimationPlayer) as a child.")
	return warnings


# ============================================================================================ public
## True once health has reached 0.
func is_dead() -> bool:
	return state == State.DEAD


## True while a start_dormant monster still waits for its wake-up.
func is_dormant() -> bool:
	return _dormant


## Name of the current state ("IDLE", "CHASE"...).
func state_name() -> String:
	return str(State.keys()[state])


## The model's AnimationPlayer (null when there is none).
func get_animation_player() -> AnimationPlayer:
	return _ap if _ap != null else _find_animation_player()


## True when the model has a clip with this name.
func has_animation(anim: StringName) -> bool:
	var ap := get_animation_player()
	return ap != null and anim != &"" and ap.has_animation(anim)


## Plays a clip with a cross-fade (blend < 0 uses blend_time). restart: play it again from the start when it
## is already playing. Returns false when the model has no such clip.
func play_animation(anim: StringName, restart := false, blend := -1.0) -> bool:
	if not has_animation(anim):
		return false
	var ap := get_animation_player()
	ap.speed_scale = 1.0
	if ap.is_playing() and ap.current_animation == anim and not restart:
		return true
	ap.play(anim, blend_time if blend < 0.0 else blend)
	if restart:
		ap.seek(0.0, true)
	return true


## Damages the monster. from_position (optional) is where the damage came from; source (optional) is the
## attacker, which the monster then hunts. Plays Hit, or Death when health reaches 0.
func take_damage(amount: float, from_position: Vector3 = Vector3.INF, source: Node = null) -> void:
	if state == State.DEAD or not active or amount <= 0.0 or Engine.is_editor_hint():
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, health)
	if health <= 0.0:
		_die()
		return
	var was_dormant := _dormant
	if target == null:
		var attacker := source as Node3D
		if attacker == null or not attacker.is_in_group(target_group):
			attacker = _nearest_target(lose_range, false)
		if attacker != null:
			_acquire(attacker, false)
	if _dormant:                        # hurt, but nobody to hunt: wake up anyway
		_dormant = false
		if play_animation(anim_wake, true, 0.0):
			_variation_left = _length(anim_wake)
	if from_position != Vector3.INF:
		var away := global_position - from_position
		away.y = 0.0
		if away.length() > 0.01:
			_face = -away.normalized()
			velocity += away.normalized() * 1.2
	if flinch and _flinch_wait <= 0.0 and has_animation(anim_hit) and not was_dormant:
		_flinch_wait = flinch_cooldown
		_alert_left = 0.0
		_hit_len = _length(anim_hit)
		_set_state(State.HIT)
		play_animation(anim_hit, true, 0.05)


## Kills the monster at once.
func kill() -> void:
	if state != State.DEAD:
		health = 0.0
		_die()


## Brings a dead monster back (full health, collision on, IDLE).
func revive() -> void:
	health = max_health
	collision_layer = _alive_layer
	collision_mask = _alive_mask
	target = null
	_dormant = false
	_hover_now = hover_height
	_set_state(State.IDLE)
	play_animation(anim_idle, true)


## Starts hunting a node right away (it does not need to be seen first).
func hunt(new_target: Node3D) -> void:
	if new_target != null and state != State.DEAD:
		_acquire(new_target, true)


## Names of the skins in skin_textures.
func skin_names() -> PackedStringArray:
	var names := PackedStringArray()
	for k in skin_textures.keys():
		names.append(str(k))
	return names


## Switches to the next skin of skin_textures and returns its name.
func next_skin() -> String:
	var names := skin_names()
	if names.is_empty():
		return skin
	skin = names[(names.find(skin) + 1) % names.size()]
	return skin


# ============================================================================================ loop
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not active:
		return
	_clock += delta
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_flinch_wait = maxf(_flinch_wait - delta, 0.0)
	_alert_wait = maxf(_alert_wait - delta, 0.0)
	if state != State.DEAD:
		_sense(delta)
	match state:
		State.IDLE:
			_do_idle(delta)
		State.WANDER:
			_do_wander()
		State.CHASE:
			_do_chase(delta)
		State.ATTACK:
			_do_attack()
		State.HIT:
			_do_hit()
		State.DEAD:
			_want = Vector3.ZERO
	_move(delta)
	_update_hover(delta)


func _set_state(new_state: State) -> void:
	if new_state == state:
		_t = 0.0
		return
	var old := state
	state = new_state
	_t = 0.0
	_stuck = 0.0
	state_changed.emit(new_state, old)


func _enter_idle() -> void:
	_set_state(State.IDLE)
	_idle_for = randf_range(idle_time.x, idle_time.y)
	_variation_left = 0.0
	play_animation(anim_idle)


func _do_idle(delta: float) -> void:
	_want = Vector3.ZERO
	if _dormant:
		return
	if _variation_left > 0.0:
		_variation_left -= delta
		if _variation_left <= 0.0:
			_t = 0.0
			play_animation(anim_idle)
		return
	play_animation(anim_idle)
	if _t < _idle_for:
		return
	if not idle_variations.is_empty() and randf() < 0.35:
		var pick := StringName(idle_variations[randi() % idle_variations.size()])
		if play_animation(pick, true):
			_variation_left = _length(pick)
			_idle_for = randf_range(idle_time.x, idle_time.y)
			return
	if wander and wander_radius > 0.3:
		var angle := randf() * TAU
		_goal = home + Vector3(sin(angle), 0.0, cos(angle)) * randf_range(wander_radius * 0.35, wander_radius)
		_set_nav_target(_goal, true)
		_set_state(State.WANDER)
	else:
		_t = 0.0
		_idle_for = randf_range(idle_time.x, idle_time.y)


func _do_wander() -> void:
	var to := _goal - global_position
	to.y = 0.0
	var arrived := to.length() < 0.5 or (_nav_ready() and _nav.is_navigation_finished() and _t > 0.3)
	if arrived or _t > 4.0 + wander_radius * 2.0 / maxf(walk_speed, 0.1) or _stuck > 1.2:
		_enter_idle()
		return
	_go_to(_goal, walk_speed)
	_animate_move(anim_walk, walk_animation_speed, walk_speed)


func _do_chase(delta: float) -> void:
	if target == null:
		_enter_idle()
		return
	var to := _flat(target.global_position - global_position)
	_face = to.normalized() if to.length() > 0.01 else _face
	if _alert_left > 0.0:
		_alert_left -= delta
		_want = Vector3.ZERO
		return
	var dist := to.length()
	var high := absf(target.global_position.y - global_position.y) > 1.8
	if not high and _cooldown <= 0.0 and _start_attack(dist):
		return
	if dist <= attack_range * 0.85 and not high:
		_want = Vector3.ZERO           # close enough: wait for the next attack
		play_animation(anim_idle)
		return
	var speed := run_speed if use_run else walk_speed
	_go_to(target.global_position, speed)
	if use_run and has_animation(anim_run):
		_animate_move(anim_run, run_animation_speed, speed)
	else:
		_animate_move(anim_walk, walk_animation_speed, speed)


func _start_attack(dist: float) -> bool:
	var reach2 := attack2_range if attack2_range > 0.0 else attack_range
	var can1 := has_animation(anim_attack) and dist <= attack_range
	var can2 := has_animation(anim_attack2) and dist <= reach2
	if not can1 and not can2:
		return false
	var second := can2 and (not can1 or randf() < attack2_chance)
	_attack_anim = anim_attack2 if second else anim_attack
	_attack_hit = attack2_hit_time if second else attack_hit_time
	_attack_reach = (reach2 if second else attack_range) + hit_reach
	_attack_len = _length(_attack_anim)
	_attack_done = false
	_want = Vector3.ZERO
	_set_state(State.ATTACK)
	play_animation(_attack_anim, true, 0.1)
	attack_started.emit(_attack_anim)
	return true


func _do_attack() -> void:
	_want = Vector3.ZERO
	if target != null and not _attack_done:
		var to := _flat(target.global_position - global_position)
		if to.length() > 0.01:
			_face = to.normalized()
	if not _attack_done and _t >= _attack_hit:
		_attack_done = true
		_land_blow()
	if _t >= _attack_len:
		_cooldown = attack_cooldown
		if target != null:
			_set_state(State.CHASE)
		else:
			_enter_idle()


func _land_blow() -> void:
	if target == null or not is_instance_valid(target) or _is_dead(target):
		return
	var to := target.global_position - global_position
	if absf(to.y) > 2.0:
		return
	to.y = 0.0
	if to.length() > _attack_reach:
		return
	var front := global_transform.basis.z
	front.y = 0.0
	if to.length() > 0.2 and front.length() > 0.01 and rad_to_deg(front.angle_to(to)) > hit_angle:
		return
	if target.has_method("take_damage"):
		target.call("take_damage", damage, global_position)
	attack_landed.emit(target, damage)


func _do_hit() -> void:
	_want = Vector3.ZERO
	if _t >= _hit_len:
		if target != null:
			_set_state(State.CHASE)
		else:
			_enter_idle()


func _die() -> void:
	_set_state(State.DEAD)
	_want = Vector3.ZERO
	velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
	target = null
	play_animation(anim_death, true, 0.1)
	collision_layer = 0                 # bullets, players and monsters pass through the body
	collision_mask = sight_mask         # ...but it still lies on the level geometry
	died.emit()
	if remove_after > 0.0:
		get_tree().create_timer(remove_after).timeout.connect(queue_free)


# ============================================================================================ senses
func _sense(delta: float) -> void:
	_sense_wait -= delta
	if _sense_wait > 0.0:
		return
	_sense_wait = 0.2
	if target != null and (not is_instance_valid(target) or not target.is_inside_tree() or _is_dead(target)):
		_drop_target()
	if target == null:
		var found := _nearest_target(detect_range, need_line_of_sight)
		if found != null:
			_acquire(found, true)
		return
	var dist := _flat(target.global_position - global_position).length()
	if dist > lose_range:
		_drop_target()
		return
	if not need_line_of_sight or _can_see(target):
		_unseen = 0.0
	else:
		_unseen += 0.2
		if _unseen > forget_time:
			_drop_target()


func _acquire(new_target: Node3D, alert: bool) -> void:
	var was_hunting := target != null
	target = new_target
	_unseen = 0.0
	if not was_hunting:
		target_spotted.emit(new_target)
	if state == State.IDLE or state == State.WANDER:
		_set_state(State.CHASE)
		_alert_left = 0.0
		if _dormant:
			_dormant = false
			if play_animation(anim_wake, true, 0.0):
				_alert_left = _length(anim_wake)
				_alert_wait = 12.0
		elif alert and _alert_wait <= 0.0 and play_animation(anim_alert, true, 0.15):
			_alert_left = _length(anim_alert)
			_alert_wait = 12.0


func _drop_target() -> void:
	if target == null:
		return
	target = null
	target_lost.emit()
	if state == State.CHASE:
		_enter_idle()


func _nearest_target(max_range: float, need_sight: bool) -> Node3D:
	var best: Node3D = null
	var best_dist := max_range
	for node in get_tree().get_nodes_in_group(target_group):
		var candidate := node as Node3D
		if candidate == null or candidate == self or _is_dead(candidate):
			continue
		var dist := _flat(candidate.global_position - global_position).length()
		if dist <= best_dist and (not need_sight or _can_see(candidate)):
			best = candidate
			best_dist = dist
	return best


func _can_see(other: Node3D) -> bool:
	var from := global_position + Vector3.UP * eye_height
	var to := other.global_position + Vector3.UP * minf(eye_height, 1.2)
	var query := PhysicsRayQueryParameters3D.create(from, to, sight_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == other


func _is_dead(node: Node) -> bool:
	return node.has_method("is_dead") and bool(node.call("is_dead"))


# ============================================================================================ moving
func _go_to(goal: Vector3, speed: float) -> void:
	var next := goal
	if _nav_ready():
		_set_nav_target(goal, false)
		var p := _nav.get_next_path_position()
		if not _nav.is_navigation_finished() and _flat(p - global_position).length() > 0.05:
			next = p
	var dir := _flat(next - global_position)
	if dir.length() < 0.05:
		_want = Vector3.ZERO
		return
	dir = dir.normalized()
	_want = dir * speed
	_face = dir


func _set_nav_target(goal: Vector3, force: bool) -> void:
	if _nav_ready() and (force or _nav.target_position.distance_to(goal) > 0.5):
		_nav.target_position = goal


func _nav_ready() -> bool:
	if not use_navigation or _nav == null:
		return false
	if _clock >= _nav_check:
		_nav_check = _clock + 1.0
		var map := _nav.get_navigation_map()
		_nav_ok = map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 \
				and not NavigationServer3D.map_get_regions(map).is_empty()
	return _nav_ok


func _move(delta: float) -> void:
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z).lerp(_want, 1.0 - exp(-acceleration * delta))
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z
	if gravity > 0.0 and not is_on_floor():
		velocity.y -= gravity * delta
	elif gravity <= 0.0:
		velocity.y = 0.0
	move_and_slide()
	var wanted := _want.length()
	if wanted > 0.1 and _t > 0.5 and Vector3(velocity.x, 0.0, velocity.z).length() < wanted * 0.25:
		_stuck += delta
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	if _face.length_squared() > 0.0001 and state != State.DEAD:
		var parent_yaw := 0.0
		var parent := get_parent() as Node3D
		if parent != null:
			parent_yaw = parent.global_rotation.y
		var yaw := atan2(_face.x, _face.z) - parent_yaw
		rotation.y = rotate_toward(rotation.y, yaw, deg_to_rad(turn_speed) * delta)


func _animate_move(anim: StringName, clip_speed: float, top_speed: float) -> void:
	if not play_animation(anim):
		play_animation(anim_idle)
		return
	if clip_speed > 0.0 and _ap != null:
		var speed := maxf(Vector3(velocity.x, 0.0, velocity.z).length(), top_speed * 0.5)
		_ap.speed_scale = clampf(speed / clip_speed, 0.5, 2.0)


func _update_hover(delta: float) -> void:
	if model == null or hover_height <= 0.0:
		return
	var want := 0.0 if state == State.DEAD else hover_height
	_hover_now = move_toward(_hover_now, want, delta * maxf(hover_height, 0.1) * 1.5)
	var bob := 0.0
	if state != State.DEAD and hover_period > 0.0:
		bob = sin(_clock * TAU / hover_period) * hover_bob
	model.position.y = _model_y + _hover_now + bob


# ============================================================================================ setup
func _setup_animations() -> void:
	if _ap == null:
		push_warning("%s: no AnimationPlayer found under the monster." % name)
		return
	for anim_name in loop_animations:
		if _ap.has_animation(anim_name):
			_ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


func _find_animation_player() -> AnimationPlayer:
	if animation_player != null:
		return animation_player
	var found := find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


func _find_navigation_agent() -> NavigationAgent3D:
	for child in get_children():
		if child is NavigationAgent3D:
			return child as NavigationAgent3D
	return null


func _length(anim: StringName) -> float:
	var ap := get_animation_player()
	if ap == null or not ap.has_animation(anim):
		return 0.0
	return ap.get_animation(anim).length


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ============================================================================================ skins
func _apply_skin_when_ready() -> void:
	if is_node_ready():
		_apply_skin()


## Puts the skin texture on every surface of the model (surface override materials shared by all monsters
## with the same skin). Works while the PSX shader of shaders/apply_psx.gd is on, too.
func _apply_skin() -> void:
	var texture: Texture2D = null
	if skin != "" and skin_textures.has(skin):
		texture = skin_textures[skin] as Texture2D
	var root: Node = model if model != null else self
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var originals: Array = mi.get_meta(PSX_META) if mi.has_meta(PSX_META) else []
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s)
			var own_texture: Texture2D = (base as BaseMaterial3D).albedo_texture if base is BaseMaterial3D else null
			var wanted := texture if texture != null else own_texture
			var skinned := _skinned(base, own_texture, wanted)
			var override: Material = null if skinned == base else skinned
			if s < originals.size():
				originals[s] = override
				var psx := mi.get_surface_override_material(s)
				if psx is ShaderMaterial:
					mi.set_surface_override_material(s, _skinned(psx, own_texture, wanted))
			else:
				mi.set_surface_override_material(s, override)


static func _skinned(material: Material, own_texture: Texture2D, texture: Texture2D) -> Material:
	if material == null or texture == null:
		return material
	var current: Texture2D = null
	if material is BaseMaterial3D:
		current = (material as BaseMaterial3D).albedo_texture
	elif material is ShaderMaterial:
		current = (material as ShaderMaterial).get_shader_parameter("albedo_texture") as Texture2D
	if current == texture or current == null:
		return material
	var key := "%d:%d" % [material.get_instance_id(), texture.get_instance_id()]
	if _skin_cache.has(key):
		return _skin_cache[key]
	var copy := material.duplicate() as Material
	if copy is BaseMaterial3D:
		var m := copy as BaseMaterial3D
		m.albedo_texture = texture
		if m.emission_texture != null and (m.emission_texture == current or m.emission_texture == own_texture):
			m.emission_texture = texture
	elif copy is ShaderMaterial:
		var sm := copy as ShaderMaterial
		sm.set_shader_parameter("albedo_texture", texture)
		var emission := sm.get_shader_parameter("emission_texture") as Texture2D
		if emission != null and (emission == current or emission == own_texture):
			sm.set_shader_parameter("emission_texture", texture)
	_skin_cache[key] = copy
	return copy
