extends Control

## Menu hauntings - the cracks.
##
## One thing happens on the main menu, on its own schedule: CRACKS race across
## the glass, branch like real impact fractures, glitch, and are gone.
##
## There used to be a face that faded in behind the title as well. It was
## removed - see the note at the bottom of this file.
##
## Restraint is the point: short bursts, long gaps. If the player can look
## directly at it and study it, it stops being unsettling.

@export_group("Crack")
## Seconds before the first crack.
@export var crack_first_delay := 6.0
## Gap between cracks.
@export var crack_min_gap := 16.0
@export var crack_max_gap := 34.0
## How long the mains take to race across.
@export var crack_draw_seconds := 0.36
## How long they stay before glitching away.
@export var crack_hold_seconds := 0.5
## How long the glitch-out lasts.
@export var crack_glitch_seconds := 0.30
## How many mains radiate from the impact point.
@export var crack_mains := 3
## How deep the branching goes. 2 is already a lot of lines.
@export var crack_depth := 2
## Chance a branch spawns at each step along a crack.
@export_range(0.0, 1.0) var crack_branch_chance := 0.28
## Line width of the bright core.
@export var crack_width := 1.7
@export var crack_color := Color(0.94, 0.97, 1.0, 0.92)

var _crack_layer: Control
var _rng := RandomNumberGenerator.new()
var _crack_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	# Sit behind the menu's own foreground so the CRT shader still applies.
	#
	# This must be called on the PARENT: `move_child` reorders a node's own
	# children, so `self.move_child(self, 0)` asks the layer to move itself
	# among its own children and fails with "Child is not a child of this node".
	if get_parent() != null:
		get_parent().move_child(self, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_crack_layer = Control.new()
	_crack_layer.name = "CrackLayer"
	_crack_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crack_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crack_layer)

	_crack_timer = crack_first_delay


func _process(delta: float) -> void:
	_crack_timer -= delta
	if _crack_timer <= 0.0:
		_crack_timer = _rng.randf_range(crack_min_gap, crack_max_gap)
		_run_crack()


# ------------------------------------------------------------------ the crack
## A branching impact fracture.
##
## The old version was ONE wandering line, which reads as a scratch. Glass breaks
## from a point: several mains radiate outward and each throws off thinner
## branches. Width tapers with depth so the tips are finer than the origin, and
## every line gets a soft halo under a bright core so it looks like glass
## catching light rather than a pen stroke.
func _run_crack() -> void:
	var vp := size
	if vp.x < 10.0 or vp.y < 10.0:
		vp = get_viewport_rect().size

	# the impact point, kept off-centre and clear of the edges
	var origin := Vector2(
		_rng.randf_range(vp.x * 0.18, vp.x * 0.82),
		_rng.randf_range(vp.y * 0.15, vp.y * 0.85))

	var jobs: Array = []
	var lines: Array = []

	var base_yaw := _rng.randf_range(0.0, TAU)
	for m in crack_mains:
		var yaw := base_yaw + (TAU / float(crack_mains)) * float(m) \
			+ _rng.randf_range(-0.55, 0.55)
		var pts := _crack_path(origin, yaw, 0)
		if pts.size() < 2:
			continue
		_add_crack(pts, crack_width, jobs, lines)
		_spawn_branches(pts, 1, jobs, lines)

	if jobs.is_empty():
		return

	# reveal everything together, so it reads as one impact rather than a queue
	var longest := 1
	for j in jobs:
		longest = maxi(longest, (j["pts"] as PackedVector2Array).size())

	var draw := create_tween()
	for step in range(1, longest):
		draw.tween_callback(func() -> void:
			for j in jobs:
				var core: Line2D = j["core"]
				var halo: Line2D = j["halo"]
				if not is_instance_valid(core):
					continue
				var p: PackedVector2Array = j["pts"]
				var shown := PackedVector2Array(p.slice(0, mini(step + 1, p.size())))
				core.points = shown
				if is_instance_valid(halo):
					halo.points = shown)
		draw.tween_interval(crack_draw_seconds / float(maxi(longest - 1, 1)))
	await draw.finished

	await get_tree().create_timer(crack_hold_seconds).timeout

	# glitch away: jitter sideways, strobe, vanish
	var glitch := create_tween()
	for i in int(crack_glitch_seconds / 0.045):
		glitch.tween_callback(func() -> void:
			for ln in lines:
				if not is_instance_valid(ln):
					continue
				ln.position.x = _rng.randf_range(-16.0, 16.0)
				ln.modulate.a = 0.08 if _rng.randf() < 0.55 else 1.0)
		glitch.tween_interval(0.045)
	glitch.tween_callback(func() -> void:
		for ln in lines:
			if is_instance_valid(ln):
				ln.queue_free())


## One crack run: a polyline heading along `yaw`, kinking and curving as it goes.
## Deeper (thinner) cracks wander more, which is what makes branches look brittle.
func _crack_path(origin: Vector2, yaw: float, depth: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := _rng.randi_range(9, 15)
	var seg := _rng.randf_range(16.0, 32.0)
	var pos := origin
	var dir := yaw
	var wander := 0.20 + 0.18 * float(depth)
	pts.append(pos)
	for i in steps:
		dir += _rng.randf_range(-wander, wander)
		seg *= _rng.randf_range(0.82, 1.06)
		pos += Vector2(cos(dir), sin(dir)) * seg
		pts.append(pos)
	return pts


## Throw branches off a crack path, recursively.
func _spawn_branches(pts: PackedVector2Array, depth: int,
		jobs: Array, lines: Array) -> void:
	if depth > crack_depth:
		return
	for i in range(1, pts.size() - 1):
		if _rng.randf() > crack_branch_chance:
			continue
		var along := pts[i + 1] - pts[i - 1]
		if along.length() < 0.01:
			continue
		var base := atan2(along.y, along.x)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var yaw := base + side * _rng.randf_range(0.5, 1.25)
		var bpts := _crack_path(pts[i], yaw, depth)
		if bpts.size() < 2:
			continue
		var w := crack_width * pow(0.58, float(depth))
		_add_crack(bpts, w, jobs, lines)
		if depth < crack_depth:
			_spawn_branches(bpts, depth + 1, jobs, lines)


## Build the halo + core pair for one crack run and record it for the tween.
func _add_crack(pts: PackedVector2Array, width: float,
		jobs: Array, lines: Array) -> void:
	# the halo: wide, faint, sits under the core. This is the glass catching
	# light around the break, and it is most of what makes it look like glass.
	var halo := Line2D.new()
	halo.name = "CrackHalo"
	halo.points = PackedVector2Array([pts[0]])
	halo.width = maxf(width * 3.6, 2.0)
	halo.default_color = Color(crack_color.r, crack_color.g, crack_color.b, 0.10)
	halo.joint_mode = Line2D.LINE_JOINT_ROUND
	halo.begin_cap_mode = Line2D.LINE_CAP_ROUND
	halo.end_cap_mode = Line2D.LINE_CAP_ROUND
	_crack_layer.add_child(halo)

	var core := Line2D.new()
	core.name = "CrackCore"
	core.points = PackedVector2Array([pts[0]])
	core.width = maxf(width, 0.6)
	core.default_color = crack_color
	core.joint_mode = Line2D.LINE_JOINT_ROUND
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	_crack_layer.add_child(core)

	jobs.append({"core": core, "halo": halo, "pts": pts})
	lines.append(core)
	lines.append(halo)


# ---------------------------------------------------------------------------
# REMOVED: the face that used to fade in behind the title.
#
# It was built from a lit height field - skull dome, brow ridge, sunken sockets,
# nasal cavity, mouth slit - with the surface normals computed from the height
# gradient. Technically that produced real form, but at the size and opacity it
# was shown it read as silly rather than unsettling, and the user asked for it
# to go. Do not reintroduce it: a face rendered by procedural geometry at low
# alpha is the exact "obvious improvement" a later session reaches for, and it
# was already tried and rejected.
#
# The branching cracks above stayed and are the whole effect now.
# ---------------------------------------------------------------------------
