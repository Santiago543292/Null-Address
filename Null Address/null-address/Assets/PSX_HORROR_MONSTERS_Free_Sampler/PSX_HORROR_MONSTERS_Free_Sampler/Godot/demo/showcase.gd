extends Node3D
## Monster showcase of PSX Horror Monsters (bitkiln - https://bitkiln.itch.io).
##
## Every monster of the pack stands on its own plinth. The number keys play the same clip on all of them:
##   1 Idle   2 Walk   3 Run   4 Attack   5 Hit   6 Death   7 8 9 the monster's extra clips (Attack2, Scream...)
## One-shot clips repeat after a short pause. Monsters without that extra clip stand idle.
##   K next skin          P PSX shader on / off      R turntable           Space pause the clips
##   [ ] slower / faster  Tab the next monster alone, the camera swings around it (Shift+Tab: the previous one)
##   O every monster again, the camera looks along the stage
##   L name labels        H help
## The camera keys are in free_camera.gd (WASD + mouse, Q / E down / up, Shift faster).

const PSX := preload("res://shaders/apply_psx.gd")
const FreeCamera := preload("res://demo/free_camera.gd")
const BASE_CLIPS: Array[StringName] = [&"Idle", &"Walk", &"Run", &"Attack", &"Hit", &"Death"]
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0]
const HELP := "1 Idle   2 Walk   3 Run   4 Attack   5 Hit   6 Death   7 8 9 extra clips\n" + \
		"K skin   P PSX shader   R turntable   Space pause   [ ] speed   Tab one monster   O all monsters\n" + \
		"WASD + mouse fly (click to capture the mouse)   Q E down / up   Shift faster   L labels   H help   Esc mouse"

@export var psx_enabled := true
@export var title := "PSX HORROR MONSTERS"
## Centre of the stage: the monsters stand on an arc around it, facing it (the O key looks around from there).
@export var stage_center := Vector3.ZERO
@export var stage_radius := 6.0
## Half the angle covered by the arc of monsters, in degrees.
@export var stage_half_angle := 70.0

## Clip slot playing now (0 = Idle ... 5 = Death, 6-8 = extras).
var slot := 0
var turntable := false
var paused := false
var speed_index := 2

var _monsters: Array[MonsterBrain] = []
var _labels: Array[Label3D] = []
var _extras: Array[PackedStringArray] = []
var _sizes: Array[Vector3] = []
var _wait: Array[float] = []
var _focus := -1
var _labels_visible := true
var _status_wait := 0.0

@onready var _camera: FreeCamera = $Camera
@onready var _help: Label = $HUD/Help
@onready var _status: Label = $HUD/Status


func _ready() -> void:
	for stand in $Stands.get_children():
		var monster := stand.get_node_or_null("Monster") as MonsterBrain
		if monster == null:
			continue
		monster.active = false
		_monsters.append(monster)
		_labels.append(stand.get_node_or_null("Label") as Label3D)
		_extras.append(_extra_clips(monster))
		_sizes.append(stand.get_meta(&"idle_size", Vector3(0.8, 1.7, 0.8)))
		_wait.append(0.0)
	_help.text = title + "   -   " + str(_monsters.size()) + " monsters\n" + HELP
	set_slot(0)
	set_psx(psx_enabled)


## Clips of a monster that are not one of the six base clips (Attack2 first, then by name).
func _extra_clips(monster: MonsterBrain) -> PackedStringArray:
	var out := PackedStringArray()
	var ap := monster.get_animation_player()
	if ap == null:
		return out
	var names := Array(ap.get_animation_list())
	names.sort()
	if names.has("Attack2"):
		out.append("Attack2")
	for n in names:
		if not BASE_CLIPS.has(StringName(n)) and n != "Attack2" and n != "RESET":
			out.append(n)
	return out


## The clip of the current slot for monster i (empty when it has no such clip).
func slot_clip(i: int) -> StringName:
	if slot < BASE_CLIPS.size():
		return BASE_CLIPS[slot]
	var k := slot - BASE_CLIPS.size()
	return StringName(_extras[i][k]) if k < _extras[i].size() else &""


## Plays clip slot n (0-8) on every monster.
func set_slot(n: int) -> void:
	slot = clampi(n, 0, BASE_CLIPS.size() + 2)
	for i in _monsters.size():
		_wait[i] = 0.0
		_play(i, true)
	_update_labels()
	_update_status()


func _play(i: int, restart: bool) -> void:
	var clip := slot_clip(i)
	var monster := _monsters[i]
	if clip == &"" or not monster.has_animation(clip):
		monster.play_animation(&"Idle")
	else:
		monster.play_animation(clip, restart, 0.15)
	var ap := monster.get_animation_player()
	if ap != null:
		ap.speed_scale = 0.0 if paused else SPEEDS[speed_index]


## Turns the PSX shader on or off for the whole showcase.
func set_psx(on: bool) -> void:
	psx_enabled = on
	if on:
		PSX.apply(self)
	else:
		PSX.restore(self)
	_update_status()


## Every monster switches to its next skin.
func next_skins() -> void:
	var was_on := psx_enabled
	if was_on:
		PSX.restore(self)
	for m in _monsters:
		m.next_skin()
	if was_on:
		PSX.apply(self)
	_update_labels()
	_update_status()


## Shows monster i alone and swings the camera around its front (-1: every monster again, the camera looks
## along the whole stage from its centre).
func focus(i: int) -> void:
	_focus = i
	for k in _monsters.size():
		_monsters[k].visible = i < 0 or k == i
		if _labels[k] != null:
			_labels[k].visible = _labels_visible and i < 0       # alone: the name is in the status line
	if i < 0 or i >= _monsters.size():
		_camera.sweep(stage_center + Vector3(0.0, 1.7, 0.0), 0.0, maxf(stage_half_angle - 25.0, 5.0))
		return
	var m := _monsters[i]
	var size := _sizes[i]           # width, height, depth of the Idle pose (metres)
	var reach := maxf(size.y, maxf(size.x, size.z) * 0.8)
	_camera.orbit(m.global_position + Vector3.UP * size.y * 0.5, clampf(reach * 1.2 + 0.5, 1.6, 6.0), 8.0,
			m.global_rotation.y, 55.0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		set_slot(key.keycode - KEY_1)
	else:
		match key.keycode:
			KEY_K:
				next_skins()
			KEY_P:
				set_psx(not psx_enabled)
			KEY_R:
				turntable = not turntable
			KEY_SPACE:
				paused = not paused
				for i in _monsters.size():
					_play(i, false)
			KEY_BRACKETLEFT:
				speed_index = maxi(speed_index - 1, 0)
				for i in _monsters.size():
					_play(i, false)
			KEY_BRACKETRIGHT:
				speed_index = mini(speed_index + 1, SPEEDS.size() - 1)
				for i in _monsters.size():
					_play(i, false)
			KEY_TAB:
				if not _monsters.is_empty():
					var step := -1 if key.shift_pressed else 1
					focus(posmod(_focus + step, _monsters.size()) if _focus >= 0 else (0 if step > 0 else _monsters.size() - 1))
			KEY_O:
				focus(-1)
			KEY_L:
				_labels_visible = not _labels_visible
				for k in _labels.size():
					if _labels[k] != null:
						_labels[k].visible = _labels_visible and _focus < 0
			KEY_H:
				_help.visible = not _help.visible
			_:
				return
	_update_status()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for i in _monsters.size():
		var m := _monsters[i]
		var model := m.get_node_or_null("Model") as Node3D
		if model != null:
			if turntable:
				model.rotation.y = wrapf(model.rotation.y + delta * 0.7 * (0.0 if paused else 1.0), -PI, PI)
			else:
				model.rotation.y = rotate_toward(model.rotation.y, 0.0, delta * 2.5)
		if paused:
			continue
		var clip := slot_clip(i)
		var ap := m.get_animation_player()
		if ap == null or clip == &"" or not ap.has_animation(clip):
			continue
		if ap.get_animation(clip).loop_mode != Animation.LOOP_NONE or ap.is_playing():
			_wait[i] = 0.0
			continue
		_wait[i] += delta * SPEEDS[speed_index]
		if _wait[i] >= (1.4 if clip == &"Death" else 0.6):
			_wait[i] = 0.0
			_play(i, true)
	_status_wait -= delta
	if _status_wait <= 0.0:
		_status_wait = 0.5
		_update_status()


func _update_labels() -> void:
	for i in _monsters.size():
		var label := _labels[i]
		if label == null:
			continue
		var m := _monsters[i]
		var line := m.skin
		if slot >= BASE_CLIPS.size():
			var clip := slot_clip(i)
			line = (String(clip) if clip != &"" and m.has_animation(clip) else "no extra clip %d" % (slot - BASE_CLIPS.size() + 1)) + " - " + m.skin
		label.text = "%s\n%s" % [m.monster_name, line]


func _update_status() -> void:
	if not is_node_ready():
		return
	var clip := String(BASE_CLIPS[slot]) if slot < BASE_CLIPS.size() else "extra clip %d" % (slot - BASE_CLIPS.size() + 1)
	var who := ""
	if _focus >= 0 and _focus < _monsters.size():
		var m := _monsters[_focus]
		var shown := slot_clip(_focus)
		clip = String(shown) if shown != &"" and m.has_animation(shown) else clip + " (none: Idle)"
		who = "%s (%s)    " % [m.monster_name, m.skin]
	_status.text = "%sclip %d: %s    speed x%s%s    PSX shader %s    turntable %s    %d fps" % [
		who, slot + 1, clip, str(SPEEDS[speed_index]), "  (paused)" if paused else "",
		"ON" if psx_enabled else "OFF", "on" if turntable else "off", Engine.get_frames_per_second()]
