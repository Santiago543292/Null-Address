extends CharacterBody3D
class_name PlayerController3D

## Don't call this.
func _create_inputs() -> void:
	var inputs : Dictionary[String,Array] = {
		"_move_left": [KEY_A],
		"_move_right": [KEY_D],
		"_move_up": [KEY_W],
		"_move_down": [KEY_S],
		"_sprint": [KEY_SHIFT],
		"_jump": [KEY_SPACE],
		"_crouch": [KEY_CTRL],
		"_perspective": [KEY_C],
		"_switch_shoulder": [KEY_Q]
	}
	for action : String in inputs:
		match inputs.keys().find(action):
			0: move_left_action_override = action
			1: move_right_action_override = action
			2: move_up_action_override = action
			3: move_down_action_override = action
			4: sprint_action_override = action
			5: jump_action_override = action
			6: crouch_action_override = action
			7: perspective_action_override = action
			8: switch_shoulder_action_override = action
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key : Key in inputs[action]:
				var event : InputEventKey = InputEventKey.new()
				event.keycode = key
				InputMap.action_add_event(action, event)

@export_category("Overrides")
@export var camera_override : Node3D ## This will override the automatic camera selection.
@export var disable_gravity_override : bool = true ## Enables and disables the gravity override variable.
@export var gravity_override : float = 25 ## Overrides the project default gravity.
@export var move_left_action_override : String = "" ## Overrides the move left direction input action. Default "A".
@export var move_right_action_override : String = "" ## Overrides the move right direction input action. Default "D".
@export var move_up_action_override : String = "" ## Overrides the move forward direction input action. Default "W".
@export var move_down_action_override : String = "" ## Overrides the move backward direction input action. Default "S".
@export var sprint_action_override : String = "" ## Overrides the sprint input action. Default "SHIFT".
@export var jump_action_override : String = "" ## Overrides the jump input action. Default "SPACE".
@export var crouch_action_override : String = "" ## Overrides the crouch input action. Default "CTRL".
@export var perspective_action_override : String = "" ## Overrides the perspective input action. Default "C".
@export var switch_shoulder_action_override : String = "" ## Overrides the switch shoulder input action. Default "Q".

@export_category("Settings")
@export var perspective : Perspectives = Perspectives.FIRST_PERSON: ## This changes perspectives.
	set(val):
		if val != perspective:
			perspective = val
			changed_perspective.emit(perspective)
		else:
			perspective = val
@export var camera_distance : float = 3 ## Changes distance between the player and the camera in third person.
@export var third_person_offset : Vector3 = Vector3(1,0,0)
@export var movement_speed : float = 400 ## The speed of the movement.
@export var movement_sprint_speed : float = 600 ## The movement speed when sprinting.
@export var movement_drag : float = 7 ## Low values are like ice and high values is more snappy.
@export var jump_force : float = 5 ## How high the jump is.
@export var crouch_height : float = 1.5 ## This changes the collision shape's height whether it is a capsule or cylinder. Be mindful though setting this. Make sure the radius supports this height, otherwise it might conflict.
@export var camera_crouch_offset : float = -0.25 ## This is the y axis position of the camera when crouched.
@export var crouch_raycast_height : float = 1.25 ## This is the raycast's target position height. This allows you to fine adjust when it is allowed to crouch. To debug, simply enable visible collisions, turn off any obstructive models, and go in third person.
@export var sensitivity : float = 0.06 ## The camera look sensitivity.
@export var air_strafe_ratio : float = 1 ## The movement difference when in the air. 1 means no change in speed and 0 means no movement when in the air. Higher values will mean you'll have faster movement in the air.
@export var air_strafe_drag : float = 3 ## Same as movement drag but when not in contact with the floor. Low values are like ice and high values is more snappy.
@export var disable_third_person_smooth : bool = false ## Makes the position of the spring arm snappy when true.
@export var disable_transition : bool = false ## Makes changing perspectives snappy when true.
@export var disable_movement : bool = false ## Keeps the player from moving when true.
@export var disable_sprint : bool = false ## Keeps the player from sprinting when true.
@export var disable_jump : bool = false ## Keeps the player from jumping when true.
@export var disable_camera_look : bool = false ## Keeps the player from being able to look around using the mouse when true.
@export var disable_mouse_control : bool = false ## The mouse mode wont be controlled by the player controller when true.

signal changed_perspective(new_perspective : Perspectives)
signal switched_shoulders()

enum Perspectives {FIRST_PERSON, THIRD_PERSON} ## All included perspective types.

var movement_direction : Vector3 ## Gives you the direction of the movement.
var sprinting : bool ## Tells you whether the player is sprinting or not.
var crouching : bool ## Tells you whether the player is crouching or not.
var _current_camera : Camera3D
var _origin_camera : Vector3
var _current_shapes : Array[CollisionShape3D]
var _current_shape_heights : Array[float]
var _current_spring_arm : SpringArm3D
var _origin_spring_arm_pos : Vector3
var _current_raycast : RayCast3D = RayCast3D.new()

func _ready() -> void:
	_current_raycast.name = "_ceiling_raycast"
	_current_raycast.add_exception(self)
	add_child(_current_raycast)
	child_order_changed.connect(_update)
	_update()
	_origin_camera = _current_camera.position
	_origin_spring_arm_pos = _current_spring_arm.position
	_current_spring_arm.top_level = true
	if move_left_action_override == "" or move_right_action_override == "" or move_up_action_override == "" or move_down_action_override == "" or sprint_action_override == "" or jump_action_override == "":
		_create_inputs()

## Don't call this.
func _update() -> void:
	if camera_override:
		_current_camera = camera_override
	else:
		_current_camera = null
		_current_shapes = []
		_current_spring_arm = null
		for child in get_children():
			if child is Camera3D:
				if child.current:
					_current_camera = child
			elif child is SpringArm3D:
				_current_spring_arm = child
				for sa_child in child.get_children():
					if sa_child is Camera3D:
						if sa_child.current:
							_current_camera = sa_child
			elif child is CollisionShape3D:
				_current_shapes.append(child)

func _reset_shape_heights() -> void:
	var index : int = 0
	for height : float in _current_shape_heights:
		_current_shapes[index].shape.height = height
		index += 1

func _capture_and_set_shape_heights(height : float) -> void:
	_current_shape_heights = []
	for shape : CollisionShape3D in _current_shapes:
		if shape.shape is CapsuleShape3D or shape.shape is CylinderShape3D:
			_current_shape_heights.append(shape.shape.height)
			shape.shape.height = height
		else:
			_current_shape_heights.append(0)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(perspective_action_override):
		if _current_spring_arm:
			if perspective == 0:
				_current_spring_arm.position = _rotated(_origin_spring_arm_pos + third_person_offset, global_rotation) + global_position
				_current_spring_arm.rotation.x = _current_camera.rotation.x
				perspective = 1
			else:
				if disable_transition:
					_current_camera.position = Vector3.ZERO ## Spring arm takes time to react, this speeds it up.
				_current_spring_arm.position = _rotated(_origin_spring_arm_pos, global_rotation) + global_position
				_current_camera.rotation.x = _current_spring_arm.rotation.x
				perspective = 0
		else:
			push_warning("There is no spring arm directly attached!")
	elif event.is_action_pressed(switch_shoulder_action_override):
		third_person_offset.x = -third_person_offset.x
		switched_shoulders.emit()
	elif event.is_action_pressed(crouch_action_override) and not crouching:
		_capture_and_set_shape_heights(crouch_height)
		if not is_on_floor():
			position.y += crouch_height / 2
		crouching = true
	elif not Input.is_action_pressed(crouch_action_override) and crouching and not _current_raycast.is_colliding():
		_reset_shape_heights()
		crouching = false
	if not _current_camera or disable_camera_look: return
	if event is InputEventMouseMotion and get_window().has_focus():
		if perspective == Perspectives.FIRST_PERSON:
			rotation.y -= event.relative.x * sensitivity * 0.1
			_current_camera.rotation.x -= event.relative.y * sensitivity * 0.1
			_current_camera.rotation.x = clampf(_current_camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		else:
			rotation.y -= event.relative.x * sensitivity * 0.1
			_current_spring_arm.rotation.x -= event.relative.y * sensitivity * 0.1
			_current_spring_arm.rotation.x = clampf(_current_spring_arm.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	if crouching:
		_current_camera.position.y = camera_crouch_offset
	else:
		_current_camera.position.y = _origin_camera.y
	if perspective == Perspectives.FIRST_PERSON:
		if _current_spring_arm:
			if disable_transition:
				if not is_zero_approx(_current_spring_arm.spring_length):
					_current_camera.position = Vector3.ZERO ## Spring arm takes time to react, this speeds it up.
				_current_spring_arm.spring_length = 0
			else:
				_current_spring_arm.spring_length = lerpf(_current_spring_arm.spring_length, 0, 0.5)
			_current_spring_arm.position = _rotated(_origin_spring_arm_pos, global_rotation) + global_position
			_current_spring_arm.rotation = global_rotation
	else:
		if _current_spring_arm:
			if disable_transition:
				if not is_equal_approx(_current_spring_arm.spring_length, camera_distance):
					_current_camera.position.z = camera_distance
				_current_spring_arm.spring_length = camera_distance
			else:
				_current_spring_arm.spring_length = lerpf(_current_spring_arm.spring_length, camera_distance, 0.5)
			if disable_third_person_smooth:
				_current_spring_arm.position = _rotated(_origin_spring_arm_pos + third_person_offset, global_rotation) + global_position
			else:
				_current_spring_arm.position = lerp(_current_spring_arm.position, _rotated(_origin_spring_arm_pos + third_person_offset, global_rotation) + global_position, 0.5)
			_current_spring_arm.rotation.y = global_rotation.y
			_current_spring_arm.rotation.z = global_rotation.z
			_current_camera.rotation.x = 0

func _physics_process(delta: float) -> void:
	_current_raycast.target_position.y = crouch_raycast_height
	sprinting = Input.is_action_pressed(sprint_action_override) and not disable_movement
	movement_direction = Vector3(Input.get_axis(move_left_action_override, move_right_action_override), 0, Input.get_axis(move_up_action_override, move_down_action_override)) * ((1 if is_on_floor() else air_strafe_ratio) if not disable_movement else 0)
	movement_direction = movement_direction.normalized().rotated(Vector3(0,1,0), rotation.y)
	if not disable_mouse_control:
		if get_window().has_focus():
			if Input.mouse_mode != Input.MouseMode.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MouseMode.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MouseMode.MOUSE_MODE_VISIBLE
	var gravity : float = gravity_override if not disable_gravity_override else ProjectSettings.get_setting("physics/3d/default_gravity")
	if is_on_floor():
		velocity.y = 0
		if Input.is_action_pressed(jump_action_override) and not disable_jump and not disable_movement:
			velocity.y += jump_force
	else: 
		velocity.y -= gravity * delta
	var movement : Vector3 = movement_direction * (movement_sprint_speed if sprinting and Input.is_action_pressed(move_up_action_override) and not disable_sprint else movement_speed) * delta
	velocity.x = lerpf(velocity.x, movement.x, (movement_drag if is_on_floor() else air_strafe_drag) * delta)
	velocity.z = lerpf(velocity.z, movement.z, (movement_drag if is_on_floor() else air_strafe_drag) * delta)
	move_and_slide()

func _rotated(vector : Vector3,rotate_vector : Vector3) -> Vector3:
	return vector.rotated(Vector3(1,0,0),rotate_vector.x).rotated(Vector3(0,1,0),rotate_vector.y).rotated(Vector3(0,0,1),rotate_vector.z)
