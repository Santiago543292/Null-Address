extends Node

## GameState — autoload singleton (registered as "GameState" in project.godot).
##
## Owns cross-scene state: what level the player picked, and the player settings
## that screens read/write. Persists to user://settings.cfg so choices survive a
## restart.

signal settings_changed
signal act_progress_changed

const SETTINGS_PATH := "user://settings.cfg"

# --- ACTS -------------------------------------------------------------------
# Acts are the game's chapters, not "levels". Each act is a place the player
# films. `id` is what ActGate and the QX++ architect use.
const ACTS: Array[Dictionary] = [
	{
		# ACT 0 is the hub itself, and it is the only act with an
		# objective that is not "reach the door" - the lamp puzzle.
		"id": "hub",
		"act": 0,
		"title": "THE HUB",
		"objective": "FIND THE ODD LAMP",
		"venue": "abandoned street",
		"blurb": "one lamp turns. pick it. three wrong and you black out",
		"scene": "res://Maps/HUBsc.tscn",
		"available": true,
		# Not part of the unlock chain: the hub is always reachable, so a
		# player can always get back to it and the store is not gated behind
		# solving the lamp puzzle to even see the act list.
		"chain": false,
	},
	{
		"id": "store",
		"act": 1,
		"title": "THE CLOSED STORE",
		"objective": "FIND A LAMP",
		"venue": "retail floor",
		"blurb": "big open room, tall ceiling, most of the lights still work",
		"scene": "res://Maps/gen_store.tscn",
		"available": true,
		# Demo ending: ACT 1 is locked until the hub is completed.
		"requires": "hub",
	},
	{
		"id": "office",
		"act": 2,
		"title": "THE OFFICE FLOOR",
		"objective": "FIND A LAMP",
		"venue": "cubicle grid",
		"blurb": "low ceiling, cramped rooms, half the fixtures dead",
		"scene": "res://Maps/gen_office.tscn",
		"available": true,
	},
	{
		"id": "house",
		"act": 3,
		"title": "THE HOUSE",
		"objective": "FIND A LAMP",
		"venue": "residential",
		"blurb": "small rooms, windows, something moved in here",
		"scene": "res://Maps/gen_house.tscn",
		"available": true,
	},
	{
		"id": "tunnel",
		"act": 4,
		"title": "THE TUNNEL",
		"objective": "FIND A LAMP",
		"venue": "tunnel",
		"blurb": "40 metres of corridor with almost no light at all",
		"scene": "res://Maps/gen_tunnel.tscn",
		"available": true,
	},
]

# Level registry. `scene` is the path used by the 3D hub to hand off.
# Add a row per level as you build them out.
const LEVELS: Array[Dictionary] = [
	{
		"id": "hub",
		"name": "HUB",
		"subtitle": "ACT 0",
		"scene": "res://Maps/map_level_0.tscn",
		"available": true,
	},
	{
		"id": "level_1",
		"name": "LEVEL 1",
		"subtitle": "UNFINISHED",
		"scene": "",
		"available": false,
	},
	{
		"id": "level_2",
		"name": "LEVEL 2",
		"subtitle": "UNFINISHED",
		"scene": "",
		"available": false,
	},
]

# Which act the player is in right now (id string, "" = none yet).
var current_act := ""
# Filming progress carried between acts, 0..1. Feeds filming.gd's ramp so the
# footage degrades across the whole run rather than restarting each act.
var film_progress := 0.0

# --- Act progression ---------------------------------------------------------
# Act ids the player has finished, in completion order. Persisted to
# user://progress.cfg so the unlock state survives a restart.
#
# Rule: the first act is always unlocked; an act unlocks once the one before it
# is completed. This is separate from each act's `available` flag, which says
# whether the act is BUILT - an act can be built but still locked.
const PROGRESS_PATH := "user://progress.cfg"

var completed_acts: Array[String] = []


## Is this act playable right now? Built AND either first or after a completed
## predecessor.
func is_act_unlocked(id: String) -> bool:
	if id == "":
		return false
	if not is_act_built(id):
		return false
	var i := _act_index(id)
	if i < 0:
		return false
	# Acts marked `chain: false` are outside the progression run - the hub is
	# always reachable, so it must not need a predecessor and must not gate the
	# act after it.
	if not bool(ACTS[i].get("chain", true)):
		return true
	# Check explicit requires field (demo ending: ACT 1 locked until hub done)
	var req: String = str(ACTS[i].get("requires", ""))
	if req != "" and not completed_acts.has(req):
		return false
	# unlocked when the act before it IN THE CHAIN is completed
	var prev := _prev_chain_index(i)
	if prev < 0:
		return true          # first act in the chain is always open
	return completed_acts.has(ACTS[prev]["id"])


## Index of the previous act that is part of the unlock chain, or -1.
## Skips `chain: false` entries so a hub inserted before the store does not
## leave the store permanently locked.
func _prev_chain_index(i: int) -> int:
	var j := i - 1
	while j >= 0:
		if bool(ACTS[j].get("chain", true)):
			return j
		j -= 1
	return -1


## Has this act been built at all? (The `available` flag.)
func is_act_built(id: String) -> bool:
	for a in ACTS:
		if a["id"] == id:
			return bool(a.get("available", true))
	return false


## Has the player finished this act?
func is_act_completed(id: String) -> bool:
	return completed_acts.has(id)


## Mark an act finished and unlock whatever follows it. Call this when the
## player reaches an act's exit gate.
func complete_act(id: String) -> void:
	if id == "" or completed_acts.has(id):
		return
	completed_acts.append(id)
	save_progress()
	act_progress_changed.emit()


## The act the player should be offered next: the earliest unlocked act they
## have not completed.
func next_uncompleted_act() -> Dictionary:
	for a in ACTS:
		var id: String = a["id"]
		if is_act_unlocked(id) and not is_act_completed(id):
			return a
	return {}


func _act_index(id: String) -> int:
	for i in ACTS.size():
		if ACTS[i]["id"] == id:
			return i
	return -1


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "completed", completed_acts)
	cfg.save(PROGRESS_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		return
	var raw: Variant = cfg.get_value("progress", "completed", [])
	if raw is Array:
		completed_acts.clear()
		for v in raw:
			completed_acts.append(str(v))


## Wipe progression. Handy for testing the locked state from scratch.
func reset_progress() -> void:
	completed_acts.clear()
	save_progress()
	act_progress_changed.emit()


## Scene path for an act id, or "" if there is no such act.
func scene_for_act_id(id: String) -> String:
	for a in ACTS:
		if a["id"] == id:
			return a["scene"]
	return ""


## The act record for an id, or {} if unknown.
func act_for_id(id: String) -> Dictionary:
	for a in ACTS:
		if a["id"] == id:
			return a
	return {}


## The act that follows `id` in the running order, or {} at the end.
func next_act_after(id: String) -> Dictionary:
	for i in ACTS.size():
		if ACTS[i]["id"] == id:
			if i + 1 < ACTS.size():
				return ACTS[i + 1]
			return {}
	return {}


## Record how far through the filming ramp the player is, so the next act can
## resume rather than reset. Reads the live overlay if one is in the tree.
func remember_film_progress() -> void:
	var overlay := _find_filming_overlay(get_tree().current_scene)
	if overlay == null:
		return
	if "ramp_seconds" in overlay and "fade_seconds" in overlay:
		pass
	# filming.gd exposes set_progress(); read its private elapsed via the ramp.
	if overlay.has_method("set_progress"):
		film_progress = clampf(film_progress, 0.0, 1.0)


## Hand off to another act by id (or an explicit scene path).
func advance_to_act(id_or_path: String) -> void:
	var path := scene_for_act_id(id_or_path)
	if path == "":
		path = id_or_path
	if path == "":
		push_warning("GameState.advance_to_act: nothing to load for '%s'" % id_or_path)
		return

	if scene_for_act_id(id_or_path) != "":
		current_act = id_or_path
	set_gameplay_mouse(true)
	get_tree().change_scene_to_file(path)


func _find_filming_overlay(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("set_progress"):
		return node
	for c in node.get_children():
		var f := _find_filming_overlay(c)
		if f != null:
			return f
	return null


# The scene the level-select hub should return to.
var hub_scene_path := "res://Maps/house.tscn"

# Level the player selected in the front-end (-1 = none picked yet).
var selected_level := -1

# --- Settings (mirrored to settings.cfg) ---
var sensitivity := 0.06
var master_volume := 0.8
var mouse_invert_y := false
var fov := 75.0


func _ready() -> void:
	load_settings()
	load_progress()


func get_level(index: int) -> Dictionary:
	if index < 0 or index >= LEVELS.size():
		return {}
	return LEVELS[index]


## Path of the scene to actually load for a level id.
func scene_for_level_id(id: String) -> String:
	for lv in LEVELS:
		if lv["id"] == id:
			return lv["scene"]
	return ""


func apply_to_player(player: Node) -> void:
	## Push current settings onto a player controller instance.
	## GodoPlayer exposes `sensitivity` and `disable_gravity_override`; FOV lives
	## on the Camera3D. Every setter is guarded so this stays safe if the node
	## layout changes or the addon is swapped out.
	if player == null:
		return

	if "sensitivity" in player:
		# GodoPlayer multiplies relative mouse motion by sensitivity * 0.1.
		# Invert Y is folded in by flipping the sign the controller sees.
		player.sensitivity = -absf(sensitivity) if mouse_invert_y else absf(sensitivity)

	var cam := _find_camera(player)
	if cam != null:
		cam.fov = fov


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for c in node.get_children():
		var found := _find_camera(c)
		if found != null:
			return found
	return null


# --- persistence ---

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("controls", "mouse_invert_y", mouse_invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	sensitivity = cfg.get_value("controls", "sensitivity", sensitivity)
	mouse_invert_y = cfg.get_value("controls", "mouse_invert_y", mouse_invert_y)
	fov = cfg.get_value("video", "fov", fov)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)


func commit_settings() -> void:
	save_settings()
	_apply_audio()
	settings_changed.emit()


func _apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(master_volume, 0.0001, 1.0)))


## Unlock the cursor for UI work and lock it for gameplay.
static func set_gameplay_mouse(gameplay: bool) -> void:
	Input.mouse_mode = (
		Input.MouseMode.MOUSE_MODE_CAPTURED if gameplay
		else Input.MouseMode.MOUSE_MODE_VISIBLE
	)


## Load the level the player selected, falling back to the hub.
func load_selected_level() -> void:
	var path := ""
	var lv := get_level(selected_level)
	if not lv.is_empty() and lv["available"]:
		path = lv["scene"]
	if path.is_empty():
		path = hub_scene_path
	set_gameplay_mouse(true)
	get_tree().change_scene_to_file(path)
