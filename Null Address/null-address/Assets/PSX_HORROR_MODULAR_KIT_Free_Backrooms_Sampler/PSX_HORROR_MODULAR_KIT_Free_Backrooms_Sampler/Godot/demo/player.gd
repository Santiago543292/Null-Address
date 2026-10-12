extends CharacterBody3D
## First-person player of the PSX Horror Modular Kit demo (bitkiln - https://bitkiln.itch.io).
##
## WASD or the arrow keys walk, the mouse looks around (click into the window to capture the mouse), Shift runs,
## Space jumps, F switches the flashlight, E uses what the crosshair points at (doors, holes, ladders) and Esc
## frees the mouse. The input actions are added at start when the project does not define them, so player.tscn
## also works when you copy it into your own project.
##
## Steps up to step_height are climbed on their own (porch steps, sewer walkways, rubble). The kit stairs carry
## a smooth ramp collider in the MeshLibraries, so they need no stepping at all.

## Walking speed in metres per second.
@export var walk_speed := 2.6
## Speed while Shift is held.
@export var run_speed := 4.8
## How quickly the player reaches the wanted speed on the ground (higher = snappier).
@export var acceleration := 12.0
## The same in the air.
@export var air_control := 2.0
@export var jump_velocity := 4.2
@export var mouse_sensitivity := 0.0025
## Highest step the player walks up without jumping, in metres.
@export var step_height := 0.32
## Height of the camera above the feet.
@export var eye_height := 1.6

## Off while a scripted move runs (climbing through a hole, up a ladder).
var input_enabled := true

var _pitch := 0.0
var _target: Node = null
var _message_time := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var flashlight: SpotLight3D = $Head/Camera/Flashlight
@onready var ray: RayCast3D = $Head/Camera/Interact
@onready var shape: CollisionShape3D = $Shape
@onready var prompt: Label = $HUD/Prompt
@onready var message: Label = $HUD/Message
@onready var fade: ColorRect = $HUD/Fade

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
}


## Adds the player's input actions with their default keys unless the project already has them. Physical keys,
## so WASD stays in place on any keyboard layout.
static func ensure_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _ready() -> void:
	ensure_actions()
	add_to_group("player")
	ray.add_exception(self)
	head.position.y = eye_height
	_pitch = camera.rotation.x
	fade.color.a = 0.0
	message.text = ""
	prompt.text = ""


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	var key := event as InputEventKey
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif motion != null:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		look(motion.relative)
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("interact"):
		use()
	else:
		return
	get_viewport().set_input_as_handled()


## Turns the view by a mouse movement in pixels.
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, deg_to_rad(-88.0), deg_to_rad(88.0))
	camera.rotation.x = _pitch


## Turns the player to a heading (degrees around Y: 0 looks north (-Z), 90 west, 180 south, 270 east).
func face(yaw_degrees: float, pitch_degrees := 0.0) -> void:
	rotation.y = deg_to_rad(yaw_degrees)
	_pitch = deg_to_rad(pitch_degrees)
	camera.rotation.x = _pitch


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message.text = ""


func _physics_process(delta: float) -> void:
	_update_target()
	if not input_enabled:
		return
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if on_floor else air_control
	horizontal = horizontal.lerp(dir * speed, 1.0 - exp(-rate * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if on_floor and velocity.y <= 0.0:
		_step_up(delta)
	move_and_slide()


## Climbs a step in front of the player: when the move of this frame is blocked by something steeper than
## floor_max_angle, the same move is tried step_height higher and the player is put down on top of the step.
func _step_up(delta: float) -> bool:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0005:
		return false
	var col := KinematicCollision3D.new()
	var from := global_transform
	if not test_move(from, motion, col, safe_margin, false, 4):
		return false
	var blocked := false
	for k in col.get_collision_count():
		blocked = blocked or col.get_normal(k).angle_to(Vector3.UP) > floor_max_angle
	if not blocked:
		return false
	var up := Vector3(0.0, step_height, 0.0)
	if test_move(from, up, col):
		up = col.get_travel()
	var raised := from.translated(up)
	var ahead := motion.normalized() * maxf(motion.length(), 0.06)
	if test_move(raised, ahead, col):
		return false
	var over := raised.translated(ahead)
	if not test_move(over, Vector3(0.0, -up.y - 0.06, 0.0), col):
		return false
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false
	var landed := over.translated(col.get_travel())
	var rise := landed.origin.y - from.origin.y
	if rise < 0.01 or rise > step_height + 0.01:
		return false
	global_transform = landed
	velocity.y = 0.0
	return true


func _update_target() -> void:
	var target: Node = null
	if input_enabled and ray.is_colliding():
		target = _usable(ray.get_collider())
	_target = target
	var text := ""
	if target != null and target.has_method("get_interact_prompt"):
		text = "[E]  " + str(target.call("get_interact_prompt", self))
	if prompt.text != text:
		prompt.text = text


func _usable(collider: Object) -> Node:
	var node := collider as Node
	for i in 4:
		if node == null:
			return null
		if node.has_method("interact"):
			return node
		node = node.get_parent()
	return null


## Uses the door, hole or ladder the crosshair points at.
func use() -> void:
	if not input_enabled:
		return
	ray.force_raycast_update()
	var target := _usable(ray.get_collider()) if ray.is_colliding() else null
	if target != null:
		target.call("interact", self)


## Shows a short line of text in the middle of the screen.
func say(text: String, seconds := 2.5) -> void:
	message.text = text
	_message_time = seconds


## Moves the feet along points (global positions) in duration seconds with collision off. With use_fade the
## screen goes black for the move. turn_to: heading at the end in degrees (see face()), NAN keeps the view.
func play_path(points: PackedVector3Array, duration: float, use_fade := false, turn_to := NAN) -> void:
	if not input_enabled or points.is_empty():
		return
	input_enabled = false
	velocity = Vector3.ZERO
	shape.set_deferred("disabled", true)
	var tween := create_tween()
	if use_fade:
		tween.tween_property(fade, "color:a", 1.0, 0.35)
	var step := duration / points.size()
	for p in points:
		if use_fade:
			tween.tween_interval(step)
			tween.tween_property(self, "global_position", p, 0.0)
		else:
			tween.tween_property(self, "global_position", p, step)
	if not is_nan(turn_to):
		tween.tween_callback(face.bind(turn_to))
	if use_fade:
		tween.tween_property(fade, "color:a", 0.0, 0.45)
	await tween.finished
	shape.disabled = false
	velocity = Vector3.ZERO
	input_enabled = true
