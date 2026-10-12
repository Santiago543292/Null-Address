@tool
extends Node3D
## Maze of the PSX Horror Monsters hunt demo (bitkiln - https://bitkiln.itch.io).
##
## Builds the floor, walls, ceiling, doors and collision from a text layout, one character per square cell:
##   #  wall
##   .  corridor: concrete floor and ceiling, brick walls
##   :  corridor: concrete floor, ceiling and walls
##   ,  room: dark planks, striped wallpaper, ceiling tiles
##   ;  washroom: dirty tiles on the floor and the walls, ceiling tiles
## Row 0 is the north edge (-Z) and the maze is centred on this node. Dead ends get an old wooden door.
## The meshes are made again whenever the layout changes (also in the editor); they are not saved in the scene.
## The textures are from the free sample of the PSX Horror Texture Pack by bitkiln.

@export var layout := PackedStringArray():
	set(value):
		layout = value
		_rebuild()
## Size of one cell in metres.
@export var cell_size := 2.0:
	set(value):
		cell_size = value
		_rebuild()
@export var wall_height := 3.0:
	set(value):
		wall_height = value
		_rebuild()
## One texture repeat per this many metres.
@export var texture_metres := 2.0
## Faces are split into squares of this size (small polygons warp less with the PSX shader's affine mapping).
@export var tile := 1.0
## Physics layers of the walls and the floor.
@export_flags_3d_physics var collision_layer := 1
## The meshes are split into blocks of this many cells, so every block only gets the lights near it
## (the Compatibility renderer draws at most 8 lights per mesh).
@export var block_cells := 4

@export_group("Textures")
@export var concrete: Texture2D
@export var brick: Texture2D
@export var planks: Texture2D
@export var wallpaper: Texture2D
@export var tiles: Texture2D
@export var ceiling_tiles: Texture2D
@export var door: Texture2D

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var _blocks := {}
var _block := Vector2i.ZERO
var _materials := {}


func _ready() -> void:
	build()


func _rebuild() -> void:
	if is_node_ready():
		build()


## Number of columns and rows of the layout.
func grid_size() -> Vector2i:
	return Vector2i(layout[0].length() if not layout.is_empty() else 0, layout.size())


## World position (on the floor) of the centre of the cell at (column, row).
func cell_center(at: Vector2i) -> Vector3:
	var size := grid_size()
	var origin := Vector3(-size.x * cell_size * 0.5, 0.0, -size.y * cell_size * 0.5)
	return global_transform * (origin + Vector3((at.x + 0.5) * cell_size, 0.0, (at.y + 0.5) * cell_size))


## The layout character of a cell ("#" outside the layout).
func cell(c: Vector2i) -> String:
	if c.y < 0 or c.y >= layout.size() or c.x < 0 or c.x >= layout[c.y].length():
		return "#"
	return layout[c.y][c.x]


func is_open(c: Vector2i) -> bool:
	return cell(c) != "#"


func build() -> void:
	for child in get_children():
		if child.has_meta(&"maze_part"):
			remove_child(child)
			child.queue_free()
	if layout.is_empty():
		return
	_blocks.clear()
	_materials.clear()
	var size := grid_size()
	var origin := Vector3(-size.x * cell_size * 0.5, 0.0, -size.y * cell_size * 0.5)
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			var kind := cell(c)
			if kind == "#":
				continue
			_block = Vector2i(floori(float(x) / maxi(block_cells, 1)), floori(float(y) / maxi(block_cells, 1)))
			var p0 := origin + Vector3(x * cell_size, 0.0, y * cell_size)
			_floor(_floor_texture(kind), p0, 0.0, Vector3.UP)
			_floor(_ceiling_texture(kind), p0, wall_height, Vector3.DOWN)
			var open_sides := 0
			for d in DIRS:
				if is_open(c + d):
					open_sides += 1
				else:
					_wall(_wall_texture(kind), p0, d)
			if open_sides == 1 and door != null:
				for d in DIRS:
					if is_open(c + d):
						_door(p0, -d)
	var geometry := Node3D.new()
	geometry.name = "Geometry"
	geometry.set_meta(&"maze_part", true)
	add_child(geometry)
	var keys := _blocks.keys()
	keys.sort()
	for block in keys:
		var mesh := ArrayMesh.new()
		var tools: Dictionary = _blocks[block]
		for key in tools:
			var st: SurfaceTool = tools[key]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
		var mi := MeshInstance3D.new()
		mi.name = "Block_%d_%d" % [block.x, block.y]
		mi.mesh = mesh
		geometry.add_child(mi)
	_collision(size, origin)


func _floor_texture(kind: String) -> Texture2D:
	match kind:
		",":
			return planks
		";":
			return tiles
	return concrete


func _ceiling_texture(kind: String) -> Texture2D:
	return ceiling_tiles if kind == "," or kind == ";" else concrete


func _wall_texture(kind: String) -> Texture2D:
	match kind:
		".":
			return brick
		",":
			return wallpaper
		";":
			return tiles
	return concrete


func _tool(texture: Texture2D) -> SurfaceTool:
	var key: Variant = "none"
	if texture != null:
		key = texture
	if not _blocks.has(_block):
		_blocks[_block] = {}
	var tools: Dictionary = _blocks[_block]
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
	return tools[key]


func _material(key: Variant) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	_materials[key] = m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if key is Texture2D:
		m.albedo_texture = key as Texture2D
		m.resource_name = (key as Texture2D).resource_path.get_file().get_basename()
	return m


## Adds a quad (corners in order around it) whose front faces normal n.
func _quad(texture: Texture2D, p: PackedVector3Array, uv: PackedVector2Array, n: Vector3) -> void:
	var st := _tool(texture)
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	if (p[2] - p[0]).cross(p[1] - p[0]).dot(n) < 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_normal(n)
		st.set_uv(uv[i])
		st.add_vertex(p[i])


## Floor (or ceiling, facing down) of the cell whose north-west corner is p0, at a height.
func _floor(texture: Texture2D, p0: Vector3, height: float, n: Vector3) -> void:
	var steps := maxi(int(round(cell_size / tile)), 1)
	var step := cell_size / steps
	for i in steps:
		for j in steps:
			var a := Vector3(p0.x + i * step, height, p0.z + j * step)
			var b := a + Vector3(step, 0.0, 0.0)
			var c := a + Vector3(step, 0.0, step)
			var d := a + Vector3(0.0, 0.0, step)
			_quad(texture, PackedVector3Array([a, b, c, d]),
					PackedVector2Array([_uv(a.x, a.z), _uv(b.x, b.z), _uv(c.x, c.z), _uv(d.x, d.z)]), n)


## Wall face on the side d of the cell whose north-west floor corner is p0; it faces into the cell.
func _wall(texture: Texture2D, p0: Vector3, d: Vector2i) -> void:
	var start := p0 + Vector3(0.0, 0.0, cell_size)      # west side, running north
	var along := Vector3.FORWARD
	if d == Vector2i(0, -1):                             # north side, running east
		start = p0
		along = Vector3.RIGHT
	elif d == Vector2i(1, 0):                            # east side, running south
		start = p0 + Vector3(cell_size, 0.0, 0.0)
		along = Vector3.BACK
	elif d == Vector2i(0, 1):                            # south side, running west
		start = p0 + Vector3(cell_size, 0.0, cell_size)
		along = Vector3.LEFT
	var n := Vector3(-d.x, 0.0, -d.y)
	var steps := maxi(int(round(cell_size / tile)), 1)
	var rows := maxi(int(round(wall_height / tile)), 1)
	var w := cell_size / steps
	var h := wall_height / rows
	var u0 := (start.x * along.x + start.z * along.z)
	for i in steps:
		for j in rows:
			var a := start + along * (i * w) + Vector3.UP * (j * h)
			var b := a + along * w
			var c := b + Vector3.UP * h
			var e := a + Vector3.UP * h
			var ua := u0 + i * w
			_quad(texture, PackedVector3Array([a, b, c, e]), PackedVector2Array([_uv(ua, wall_height - a.y),
					_uv(ua + w, wall_height - a.y), _uv(ua + w, wall_height - c.y), _uv(ua, wall_height - c.y)]), n)


## Old wooden door on the wall at side d of the cell (p0 = its north-west floor corner).
func _door(p0: Vector3, d: Vector2i) -> void:
	var center := p0 + Vector3(cell_size * 0.5, 0.0, cell_size * 0.5) + Vector3(d.x, 0.0, d.y) * (cell_size * 0.5 - 0.02)
	var n := Vector3(-d.x, 0.0, -d.y)
	var side := Vector3(-n.z, 0.0, n.x)
	var half := 0.55
	var a := center - side * half
	var b := center + side * half
	var c := b + Vector3.UP * 2.1
	var e := a + Vector3.UP * 2.1
	_quad(door, PackedVector3Array([a, b, c, e]), PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]), n)


func _uv(u: float, v: float) -> Vector2:
	return Vector2(u, v) / maxf(texture_metres, 0.01)


func _collision(size: Vector2i, origin: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.set_meta(&"maze_part", true)
	add_child(body)
	var ground := BoxShape3D.new()
	ground.size = Vector3(size.x * cell_size, 1.0, size.y * cell_size)
	_add_shape(body, ground, Vector3(0.0, -0.5, 0.0))
	for y in size.y:
		var x := 0
		while x < size.x:
			if is_open(Vector2i(x, y)):
				x += 1
				continue
			var run := 0
			while x + run < size.x and not is_open(Vector2i(x + run, y)):
				run += 1
			var box := BoxShape3D.new()
			box.size = Vector3(run * cell_size, wall_height, cell_size)
			_add_shape(body, box, origin + Vector3((x + run * 0.5) * cell_size, wall_height * 0.5, (y + 0.5) * cell_size))
			x += run


func _add_shape(body: StaticBody3D, shape: Shape3D, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	body.add_child(cs)
