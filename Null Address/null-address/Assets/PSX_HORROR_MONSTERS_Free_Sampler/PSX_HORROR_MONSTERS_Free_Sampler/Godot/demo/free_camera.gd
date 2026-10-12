extends Camera3D
## Free camera of the PSX Horror Monsters showcase (bitkiln - https://bitkiln.itch.io).
##
##   W A S D / arrows  fly            mouse        look (click into the window to capture the mouse)
##   Q / E             down / up      Shift        faster
##   mouse wheel       closer / farther while orbiting                 Esc  free the mouse
## The showcase calls orbit() to swing around a monster (Tab) and sweep() to look along the stage (O);
## flying or looking around with the mouse ends both.

enum Mode { FLY, ORBIT, SWEEP }

@export var fly_speed := 3.0
@export var fast_multiplier := 3.0
@export var mouse_sensitivity := 0.0025
## Speed of the orbit and of the sweep.
@export var orbit_speed := 0.35
## The camera stays inside this box.
@export var bounds_min := Vector3(-80.0, 0.15, -80.0)
@export var bounds_max := Vector3(80.0, 40.0, 80.0)

var mode := Mode.FLY
var orbit_center := Vector3.ZERO
var orbit_distance := 4.0

var _yaw := 0.0
var _pitch := 0.0
var _t := 0.0
var _angle := 0.0
var _swing := 0.0
var _elevation := 0.2
var _sweep_yaw := 0.0
var _sweep_half := 1.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


## Circles around a point, looking at it. start_yaw: direction from the point to the camera (radians around Y,
## 0 = +Z). swing_degrees > 0: swing to and fro by that much instead of going all the way round.
func orbit(center: Vector3, distance: float, elevation_degrees := 12.0, start_yaw := 0.0, swing_degrees := 0.0) -> void:
	orbit_center = center
	orbit_distance = distance
	_elevation = deg_to_rad(elevation_degrees)
	_angle = start_yaw
	_swing = deg_to_rad(swing_degrees)
	_t = 0.0
	mode = Mode.ORBIT
	_update_orbit(0.0)


## Stands at a point and turns slowly from side to side around yaw_center (radians), half_degrees each way.
func sweep(at: Vector3, yaw_center: float, half_degrees: float, pitch_degrees := -6.0) -> void:
	global_position = at
	_sweep_yaw = yaw_center
	_sweep_half = deg_to_rad(half_degrees)
	_pitch = deg_to_rad(pitch_degrees)
	_t = 0.0
	mode = Mode.SWEEP


## Back to flying from the current view.
func fly() -> void:
	if mode == Mode.FLY:
		return
	mode = Mode.FLY
	var euler := global_transform.basis.get_euler()
	_yaw = euler.y
	_pitch = euler.x
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	var key := event as InputEventKey
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and mode == Mode.ORBIT:
			orbit_distance = maxf(orbit_distance * 0.9, 0.8)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mode == Mode.ORBIT:
			orbit_distance = minf(orbit_distance * 1.1, 60.0)
		else:
			return
		get_viewport().set_input_as_handled()
	elif motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mode == Mode.ORBIT:
			_angle -= motion.relative.x * mouse_sensitivity
			_elevation = clampf(_elevation + motion.relative.y * mouse_sensitivity, deg_to_rad(-10.0), deg_to_rad(80.0))
		else:
			fly()
			_yaw -= motion.relative.x * mouse_sensitivity
			_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, deg_to_rad(-88.0), deg_to_rad(88.0))
			rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _update_orbit(delta: float) -> void:
	_t += delta
	var a := _angle + sin(_t * orbit_speed) * _swing if _swing > 0.0 else _angle
	if _swing <= 0.0:
		_angle += orbit_speed * 0.6 * delta
	var flat := orbit_distance * cos(_elevation)
	var p := orbit_center + Vector3(sin(a) * flat, orbit_distance * sin(_elevation), cos(a) * flat)
	global_position = p.clamp(bounds_min, bounds_max)
	if global_position.distance_to(orbit_center) > 0.01:
		look_at(orbit_center, Vector3.UP)


func _process(delta: float) -> void:
	var dir := Vector3(_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT), _key(KEY_E, KEY_PAGEUP) - _key(KEY_Q, KEY_PAGEDOWN),
			_key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	if mode != Mode.FLY and dir.length() > 0.0:
		fly()
	if mode == Mode.ORBIT:
		_update_orbit(delta)
		return
	if mode == Mode.SWEEP:
		_t += delta
		_yaw = _sweep_yaw + sin(_t * orbit_speed * 0.5) * _sweep_half
		rotation = Vector3(_pitch, _yaw, 0.0)
		return
	var speed := fly_speed * (fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var move := Basis(Vector3.UP, _yaw) * Vector3(dir.x, 0.0, dir.z)
	move.y += dir.y
	if move.length() > 1.0:
		move = move.normalized()
	position = (position + move * speed * delta).clamp(bounds_min, bounds_max)
