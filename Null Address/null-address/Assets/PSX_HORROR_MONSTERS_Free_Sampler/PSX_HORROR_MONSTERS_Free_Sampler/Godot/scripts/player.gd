extends CharacterBody3D
## First-person player of the PSX Horror Monsters demo (bitkiln - https://bitkiln.itch.io).
##
## Put it on a CharacterBody3D (a capsule collision shape is added when there is none); the camera, flashlight,
## muzzle flash and HUD are built when the scene starts. The input actions are added with their default keys
## when the project does not define them, so the script also works when you copy it into your own project.
##
##   W A S D / arrows  walk         mouse        look (click into the window to capture the mouse)
##   Shift             sprint       Space        jump
##   F                 flashlight   left click   shoot (a ray; calls take_damage() on what it hits)
##   Esc               free the mouse
##
## Monsters hurt the player through take_damage(amount, from_position). At 0 health the player falls over and,
## with reload_on_death, the scene starts again.

## A shot was fired; hit is the ray result (empty when it hit nothing).
signal shot_fired(hit: Dictionary)
signal damaged(amount: float, health_left: float)
signal died

@export_group("Movement")
@export var walk_speed := 2.8
@export var sprint_speed := 5.0
## How quickly the player reaches the wanted speed (higher = snappier).
@export var acceleration := 12.0
@export var jump_velocity := 4.0
@export var mouse_sensitivity := 0.0025
## Height of the camera above the feet.
@export var eye_height := 1.6
## Off while a cut-scene or menu has control.
@export var input_enabled := true

@export_group("Health")
@export var max_health := 100.0
## Ignore all damage.
@export var invulnerable := false
## Start the scene again after death.
@export var reload_on_death := true
## Seconds between death and the restart.
@export var respawn_delay := 3.0

@export_group("Gun")
@export var shoot_damage := 34.0
## Seconds between two shots.
@export var fire_interval := 0.3
## Reach of a shot in metres.
@export var shoot_range := 60.0
## Physics layers a shot can hit (1 = level, 3 = monsters in the demo).
@export_flags_3d_physics var shoot_mask := 5

@export_group("Flashlight")
@export var flashlight_on := true
@export var flashlight_range := 16.0
@export var flashlight_energy := 2.6
@export var flashlight_angle := 27.0

@export_group("HUD")
@export var show_hud := true
## Controls shown at the bottom of the screen (an empty text hides them).
@export_multiline var controls_text := "WASD move   Shift sprint   Space jump   F flashlight   Left click shoot   Esc free the mouse"

var health := 100.0
var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var muzzle: OmniLight3D

var _pitch := 0.0
var _dead := false
var _fire_wait := 0.0
var _want_shot := false
var _muzzle_time := 0.0
var _kick := 0.0
var _shake := 0.0
var _bob := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _health_label: Label
var _controls_label: Label
var _message: Label
var _crosshair: Label
var _flash: ColorRect
var _marker_time := 0.0

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"flashlight": [KEY_F],
}


## Adds the player's input actions with their default keys unless the project already has them (physical keys,
## so WASD stays in place on every keyboard layout). The shoot action is the left mouse button.
static func ensure_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", click)


func _ready() -> void:
	ensure_actions()
	add_to_group(&"player")
	health = max_health
	_build_rig()
	_update_hud()


func _build_rig() -> void:
	if find_children("*", "CollisionShape3D", false).is_empty():
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.75
		shape.shape = capsule
		shape.position.y = 0.875
		add_child(shape)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = eye_height
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 150.0
	head.add_child(camera)
	camera.make_current()
	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.light_color = Color(1.0, 0.92, 0.76)
	flashlight.light_energy = flashlight_energy
	flashlight.light_specular = 0.0
	flashlight.spot_range = flashlight_range
	flashlight.spot_angle = flashlight_angle
	flashlight.spot_attenuation = 0.9
	flashlight.spot_angle_attenuation = 0.85
	flashlight.position = Vector3(0.12, -0.08, 0.0)
	flashlight.visible = flashlight_on
	camera.add_child(flashlight)
	muzzle = OmniLight3D.new()
	muzzle.name = "MuzzleFlash"
	muzzle.light_color = Color(1.0, 0.7, 0.35)
	muzzle.light_energy = 3.0
	muzzle.light_specular = 0.0
	muzzle.omni_range = 7.0
	muzzle.position = Vector3(0.2, -0.15, -0.6)
	muzzle.visible = false
	camera.add_child(muzzle)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.visible = show_hud
	add_child(hud)
	_flash = ColorRect.new()
	_flash.color = Color(0.55, 0.0, 0.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(_flash)
	_crosshair = _label(hud, "+", 22, Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.modulate = Color(1, 1, 1, 0.75)
	_health_label = _label(hud, "HEALTH 100", 26, Control.PRESET_TOP_LEFT)
	_controls_label = _label(hud, controls_text, 15, Control.PRESET_BOTTOM_LEFT)
	_controls_label.modulate = Color(1, 1, 1, 0.8)
	_controls_label.visible = controls_text != ""
	_message = _label(hud, "", 40, Control.PRESET_CENTER)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", Color(0.75, 0.05, 0.05))


func _label(parent: Node, text: String, size: int, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.93, 0.87, 0.78))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	if preset == Control.PRESET_CENTER:
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.grow_vertical = Control.GROW_DIRECTION_BOTH
	elif preset == Control.PRESET_BOTTOM_LEFT:
		label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return label


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	var key := event as InputEventKey
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED     # the first click only captures the mouse
	elif motion != null:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not input_enabled or _dead:
			return
		look(motion.relative)
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("shoot"):
		_want_shot = true
	else:
		return
	get_viewport().set_input_as_handled()


## Turns the view by a mouse movement in pixels.
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, deg_to_rad(-88.0), deg_to_rad(88.0))


## Turns the view to a heading and pitch in degrees (heading 0 looks along -Z).
func face(yaw_degrees: float, pitch_degrees := 0.0) -> void:
	rotation.y = deg_to_rad(yaw_degrees)
	_pitch = deg_to_rad(pitch_degrees)


## Points the camera at a world position.
func aim_at(point: Vector3) -> void:
	var from := global_position + Vector3.UP * eye_height
	var dir := point - from
	if dir.length() < 0.01:
		return
	var parent_yaw := 0.0
	var parent := get_parent() as Node3D
	if parent != null:
		parent_yaw = parent.global_rotation.y
	rotation.y = atan2(-dir.x, -dir.z) - parent_yaw
	_pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	if camera != null:
		camera.rotation.x = _pitch


func is_dead() -> bool:
	return _dead


## Damages the player (monsters call this). from_position is where the blow came from.
func take_damage(amount: float, from_position: Vector3 = Vector3.INF) -> void:
	if _dead or invulnerable or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_flash.color.a = clampf(0.25 + amount / max_health, 0.25, 0.6)
	_shake = 0.25
	if from_position != Vector3.INF:
		var away := global_position - from_position
		away.y = 0.0
		if away.length() > 0.01:
			velocity += away.normalized() * 2.0
	damaged.emit(amount, health)
	_update_hud()
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if not _dead:
		health = minf(health + amount, max_health)
		_update_hud()


## Fires one shot along the view (also used by the left mouse button). Returns the ray result.
func shoot() -> Dictionary:
	if _dead or _fire_wait > 0.0:
		return {}
	_fire_wait = fire_interval
	muzzle.visible = true
	_muzzle_time = 0.06
	_kick = 0.035
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * shoot_range
	var query := PhysicsRayQueryParameters3D.create(from, to, shoot_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var victim := _damageable(hit.get("collider") as Node)
		if victim != null:
			victim.call("take_damage", shoot_damage, global_position)
			_marker_time = 0.15
	shot_fired.emit(hit)
	return hit


func _damageable(node: Node) -> Node:
	for i in 4:
		if node == null:
			return null
		if node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null


func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	_message.text = "YOU DIED"
	var tween := create_tween()
	tween.tween_property(head, "position:y", 0.35, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(head, "rotation:z", deg_to_rad(70.0), 0.8)
	died.emit()
	if reload_on_death:
		get_tree().create_timer(respawn_delay).timeout.connect(_restart)


func _restart() -> void:
	if is_inside_tree():
		get_tree().reload_current_scene()


func _update_hud() -> void:
	if _health_label != null:
		_health_label.text = "HEALTH %d" % int(ceilf(health))
		_health_label.add_theme_color_override("font_color", Color(0.93, 0.87, 0.78) if health > max_health * 0.3 else Color(0.9, 0.2, 0.15))


func _process(delta: float) -> void:
	if _muzzle_time > 0.0:
		_muzzle_time -= delta
		if _muzzle_time <= 0.0:
			muzzle.visible = false
	if _marker_time > 0.0:
		_marker_time -= delta
		_crosshair.modulate = Color(1.0, 0.25, 0.2, 1.0) if _marker_time > 0.0 else Color(1, 1, 1, 0.75)
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 0.9)
	_kick = move_toward(_kick, 0.0, delta * 0.25)
	_shake = maxf(_shake - delta, 0.0)
	if not _dead:
		camera.rotation.x = _pitch + _kick
		camera.rotation.z = sin(Time.get_ticks_msec() * 0.07) * _shake * 0.08
		camera.position.x = sin(Time.get_ticks_msec() * 0.11) * _shake * 0.05


func _physics_process(delta: float) -> void:
	_fire_wait = maxf(_fire_wait - delta, 0.0)
	if _want_shot:
		_want_shot = false
		if input_enabled:
			shoot()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var dir := Vector3.ZERO
	var speed := walk_speed
	if input_enabled and not _dead:
		if is_on_floor() and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = transform.basis * Vector3(input.x, 0.0, input.y)
		dir.y = 0.0
		if dir.length() > 1.0:
			dir = dir.normalized()
		if Input.is_action_pressed("sprint"):
			speed = sprint_speed
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z).lerp(dir * speed, 1.0 - exp(-acceleration * delta))
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z
	move_and_slide()
	if not _dead:
		var moving := Vector2(velocity.x, velocity.z).length()
		if is_on_floor() and moving > 0.3:
			_bob += delta * moving * 2.6
		head.position.y = lerpf(head.position.y, eye_height + sin(_bob) * 0.035 * minf(moving / walk_speed, 1.5), 1.0 - exp(-14.0 * delta))
