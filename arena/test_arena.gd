class_name TestArena
extends Node3D
## Blockout test arena built in code (§7.2). North = −Z, screen-right = +X.

const CHECKER_SHADER: Shader = preload("res://arena/shaders/checker.gdshader")
const HALF_SIZE := 45.0
const WALL_THICKNESS := 1.0
const WALL_HEIGHT := 1.5
const SOUTH_WALL_HEIGHT := 0.6
const SPAWN_COUNT := 10
const SPAWN_RADIUS := 32.0
const ITEM_RING_COUNT := 8
const ITEM_RING_RADIUS := 24.0
const ITEM_HEIGHT := 0.8             # box center above the surface

var spawn_points: Array[Marker3D] = []
var item_spawn_points: Array[Marker3D] = []

func _ready() -> void:
	_build_environment()
	_build_geometry()
	_build_spawn_points()
	_build_item_spawns()

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func _build_geometry() -> void:
	var red := Color("#FF595E")
	var yellow := Color("#FFCA3A")
	var green := Color("#8AC926")
	var blue := Color("#1982C4")
	var purple := Color("#6A4C93")
	var orange := Color("#FF924C")
	var cyan := Color("#4CC9F0")

	# Floor with a world-space checker.
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = CHECKER_SHADER
	ArenaBuilder.box_with_material(self, Vector3(0.0, -0.5, 0.0), Vector3(HALF_SIZE * 2.0, 1.0, HALF_SIZE * 2.0), floor_mat)

	# Walls: inner faces on the floor edges; the south wall (camera side) is low so it barely occludes.
	var edge := HALF_SIZE + WALL_THICKNESS * 0.5
	var span := HALF_SIZE * 2.0 + WALL_THICKNESS * 2.0
	ArenaBuilder.box(self, Vector3(0.0, WALL_HEIGHT * 0.5, -edge), Vector3(span, WALL_HEIGHT, WALL_THICKNESS), purple)
	ArenaBuilder.box(self, Vector3(edge, WALL_HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, span), purple)
	ArenaBuilder.box(self, Vector3(-edge, WALL_HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, span), purple)
	ArenaBuilder.box(self, Vector3(0.0, SOUTH_WALL_HEIGHT * 0.5, edge), Vector3(span, SOUTH_WALL_HEIGHT, WALL_THICKNESS), purple)

	# Table: raised platform, top at y = 3, x −10..10, z −18..−6. North edge is an open drop.
	ArenaBuilder.box(self, Vector3(0.0, 1.5, -12.0), Vector3(20.0, 3.0, 12.0), blue)

	# Ramps up to the table: A 14° from the south, B 25° from the east, C 35° from the west.
	ArenaBuilder.wedge(self, Vector3(0.0, 0.0, 0.0), Vector3(6.0, 3.0, 12.0), 0.0, yellow)
	ArenaBuilder.wedge(self, Vector3(13.2, 0.0, -12.0), Vector3(6.0, 3.0, 6.4), 90.0, orange)
	ArenaBuilder.wedge(self, Vector3(-12.15, 0.0, -12.0), Vector3(6.0, 3.0, 4.3), -90.0, red)

	# Kicker 17°: rises north, landing zone z 18..0 stays clear.
	ArenaBuilder.wedge(self, Vector3(-25.0, 0.0, 20.0), Vector3(5.0, 1.2, 4.0), 0.0, red)

	# Humps at x = 38: pairs of up (rising north) and down (rising south) wedges.
	for start: float in [20.0, 10.0, 0.0, -10.0]:
		ArenaBuilder.wedge(self, Vector3(38.0, 0.0, start - 2.0), Vector3(6.0, 1.0, 4.0), 0.0, green)
		ArenaBuilder.wedge(self, Vector3(38.0, 0.0, start - 6.0), Vector3(6.0, 1.0, 4.0), 180.0, green)

	# Side slope ~12°: rises east, x 22..34, z −38..−26.
	ArenaBuilder.wedge(self, Vector3(28.0, 0.0, -32.0), Vector3(12.0, 2.5, 12.0), -90.0, cyan)

	# Cubes to bump into.
	for p: Vector3 in [Vector3(-15.0, 1.0, 5.0), Vector3(15.0, 1.0, 8.0), Vector3(-36.0, 1.0, 0.0), Vector3(5.0, 1.0, 25.0),
			Vector3(-8.0, 1.0, 32.0), Vector3(30.0, 1.0, -14.0), Vector3(-38.0, 1.0, 25.0), Vector3(12.0, 1.0, -30.0)]:
		ArenaBuilder.box(self, p, Vector3(2.0, 2.0, 2.0), orange)

	# Pillars on the camera side (occlusion test, M7).
	ArenaBuilder.box(self, Vector3(-12.0, 3.0, 38.0), Vector3(2.0, 6.0, 2.0), purple)
	ArenaBuilder.box(self, Vector3(12.0, 3.0, 38.0), Vector3(2.0, 6.0, 2.0), purple)

	# Charging pads in two corners.
	for p: Vector3 in [Vector3(-36.0, 0.0, -36.0), Vector3(36.0, 0.0, 36.0)]:
		var pad := ChargingPad.new()
		pad.name = "ChargingPad_%d_%d" % [int(p.x), int(p.z)]
		pad.position = p
		add_child(pad)

## 10 markers on a circle, facing the center.
func _build_spawn_points() -> void:
	for i in SPAWN_COUNT:
		var a := TAU * float(i) / float(SPAWN_COUNT)
		var pos := Vector3(sin(a), 0.0, cos(a)) * SPAWN_RADIUS
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.transform = Transform3D(Basis.looking_at(-pos.normalized(), Vector3.UP), pos)
		m.add_to_group("spawn_point")
		add_child(m)
		spawn_points.append(m)

## 8 item boxes on a circle (every 45°), one on the table, one in the kicker landing zone.
func _build_item_spawns() -> void:
	var points: Array[Vector3] = []
	for i in ITEM_RING_COUNT:
		var a := TAU * float(i) / float(ITEM_RING_COUNT)
		points.append(Vector3(sin(a) * ITEM_RING_RADIUS, ITEM_HEIGHT, cos(a) * ITEM_RING_RADIUS))
	points.append(Vector3(0.0, 3.0 + ITEM_HEIGHT, -12.0))   # table top
	points.append(Vector3(-25.0, ITEM_HEIGHT, 8.0))         # kicker landing zone
	for i in points.size():
		var m := Marker3D.new()
		m.name = "ItemSpawn%d" % i
		m.position = points[i]
		m.add_to_group("item_spawn")
		add_child(m)
		item_spawn_points.append(m)
