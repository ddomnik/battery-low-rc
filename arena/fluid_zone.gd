class_name FluidZone
extends Node3D
## A fluid in the map (water, lava, mud, acid…): a box whose top is the surface (this node sits at the
## surface center, the box reaches size.y down; only turned around the vertical). No collision: cars drive or
## sink into it. Cars ask FluidZone.at() each tick (Car._update_fluid) and react to the values here; Match
## applies the damage. Built by Arena from a "fluid" map object (see MapLoader / FluidPresets).

const SHADER: Shader = preload("res://arena/shaders/fluid.gdshader")
const BODY_HALF_HEIGHT := 0.45        # a car's body counts as fully under at origin 0.45 m below the surface
const ABOVE_MARGIN := 1.0             # a car origin this far above the surface may still touch it with its wheels
const BOTTOM_MARGIN := 0.5            # below the box bottom = not in this fluid (e.g. a tunnel under a lake)
const SURFACE_SEGMENT := 2.0          # m per surface mesh segment (waves)
const MAX_SEGMENTS := 64
const LIGHT_ENERGY := 1.6             # glowing fluids light their surroundings
const MAX_LIGHT_RANGE := 25.0
const PARTICLES_PER_M2 := 0.3
const MAX_PARTICLES := 90

static var active: Array[FluidZone] = []
static var _noise: NoiseTexture2D = null

var preset: String = "water"
var size: Vector3 = Vector3(8.0, 1.0, 8.0)
var color: Color = Color("#3E8FD6")
var opacity: float = 0.72
var texture: Texture2D = null
var damage: float = 0.0               # per 100 ms of touching
var slow: float = 1.0                 # top speed × while touching
var drag: float = 0.0
var buoyancy: float = 0.0
var grip: float = 1.0
var kill: bool = false
var current: Vector2 = Vector2.ZERO   # m/s in the fluid's own X / Z (turns with it)
var coat: float = 0.0                 # s of wet tyre tracks after leaving

var current_world: Vector3 = Vector3.ZERO
var _inverse: Transform3D = Transform3D.IDENTITY

## Sets every value from a validated "fluid" map object.
func setup(o: Dictionary, tex: Texture2D) -> void:
	transform = o["transform"]
	preset = o["preset"]
	size = o["size"]
	color = o["color"]
	opacity = o["opacity"]
	damage = o["damage"]
	slow = o["slow"]
	drag = o["drag"]
	buoyancy = o["buoyancy"]
	grip = o["grip"]
	kill = o["kill"]
	current = o["current"]
	coat = o["coat"]
	texture = tex

func _enter_tree() -> void:
	active.append(self)

func _exit_tree() -> void:
	active.erase(self)

func _ready() -> void:
	_inverse = global_transform.affine_inverse()
	current_world = global_basis * Vector3(current.x, 0.0, current.y)
	build_visual(self, preset, size, color, opacity, texture, current_world)

## The fluid containing point (horizontally inside, not more than above_margin above the surface, not below
## the bottom), or null.
static func at(point: Vector3, above_margin: float = ABOVE_MARGIN) -> FluidZone:
	for z in active:
		if z.contains(point, above_margin):
			return z
	return null

## True if a harmful fluid (damage or kill) lies at point (bots steer around these).
static func harmful_at(point: Vector3) -> bool:
	for z in active:
		if z.harmful() and z.contains(point, 3.0):
			return true
	return false

## Flat direction of the shortest way out of this fluid from point (bots that ended up inside).
func exit_direction(point: Vector3) -> Vector3:
	var l := _inverse * point
	var to_x := size.x * 0.5 - absf(l.x)
	var to_z := size.z * 0.5 - absf(l.z)
	var local := Vector3(signf(l.x) if l.x != 0.0 else 1.0, 0.0, 0.0) if to_x < to_z \
		else Vector3(0.0, 0.0, signf(l.z) if l.z != 0.0 else 1.0)
	return (global_basis * local).normalized()

## The harmful fluid at point, or null (see harmful_at).
static func harmful_zone_at(point: Vector3) -> FluidZone:
	for z in active:
		if z.harmful() and z.contains(point, 3.0):
			return z
	return null

func contains(point: Vector3, above_margin: float) -> bool:
	var l := _inverse * point
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.z * 0.5 and l.y <= above_margin and l.y >= -size.y - BOTTOM_MARGIN

## How far point is below the surface (negative: above).
func depth_of(point: Vector3) -> float:
	return -(_inverse * point).y

func harmful() -> bool:
	return damage > 0.0 or kill

## The color tyres carry out of this fluid (wet tracks, drops).
func track_color() -> Color:
	var p := FluidPresets.get_preset(preset)
	return Color(color.darkened(0.35) if preset == "water" else color, p["track_alpha"])

## The surface (and glow / particles) under parent: used by the game and by the map editor's preview.
static func build_visual(parent: Node3D, preset_name: String, fluid_size: Vector3, fluid_color: Color, fluid_opacity: float,
		tex: Texture2D, flow_world: Vector3) -> void:
	var p := FluidPresets.get_preset(preset_name)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("base_color", fluid_color)
	mat.set_shader_parameter("opacity", fluid_opacity)
	mat.set_shader_parameter("glow", p["glow"])
	mat.set_shader_parameter("crust", p.get("crust", 0.0))
	mat.set_shader_parameter("wave_height", p["waves"])
	mat.set_shader_parameter("roughness_value", p["roughness"])
	mat.set_shader_parameter("flow", Vector2(flow_world.x, flow_world.z))
	mat.set_shader_parameter("noise_tex", _noise_texture())
	if tex != null:
		mat.set_shader_parameter("pattern_tex", tex)
		mat.set_shader_parameter("use_pattern", true)
	var plane := PlaneMesh.new()
	plane.size = Vector2(fluid_size.x, fluid_size.z)
	plane.subdivide_width = clampi(int(fluid_size.x / SURFACE_SEGMENT), 1, MAX_SEGMENTS)
	plane.subdivide_depth = clampi(int(fluid_size.z / SURFACE_SEGMENT), 1, MAX_SEGMENTS)
	plane.material = mat
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = plane
	surface.layers = Layers.RENDER_FX
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(surface, false, Node.INTERNAL_MODE_BACK)
	if float(p["glow"]) > 1.0:
		var light := OmniLight3D.new()
		light.light_color = fluid_color
		light.light_energy = LIGHT_ENERGY
		light.omni_range = minf(maxf(fluid_size.x, fluid_size.z) * 0.8, MAX_LIGHT_RANGE)
		light.position = Vector3.UP * 1.5
		parent.add_child(light, false, Node.INTERNAL_MODE_BACK)
	var kind: String = p["particles"]
	if not kind.is_empty():
		parent.add_child(_ambient_particles(kind, fluid_size, fluid_color), false, Node.INTERNAL_MODE_BACK)

## Rising embers (lava) or popping bubbles (mud, acid) over the whole surface.
static func _ambient_particles(kind: String, fluid_size: Vector3, fluid_color: Color) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(fluid_size.x * 0.48, 0.05, fluid_size.z * 0.48)
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.gravity = Vector3.ZERO
	var ramp: Gradient
	if kind == "embers":
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 2.0
		pm.scale_min = 0.4
		pm.scale_max = 1.0
		ramp = ParticleFx.gradient(PackedColorArray([Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.75, 0.3), Color(1.0, 0.3, 0.05, 0.0)]))
	else:
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.2
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		var light := fluid_color.lightened(0.35)
		ramp = ParticleFx.gradient(PackedColorArray([Color(light, 0.0), light, Color(light, 0.0)]))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	var amount := clampi(int(fluid_size.x * fluid_size.z * PARTICLES_PER_M2), 4, MAX_PARTICLES)
	var particles := ParticleFx.continuous(pm, ParticleFx.spark_mesh(0.22 if kind == "embers" else 0.3), amount,
		1.6 if kind == "embers" else 1.0)
	particles.name = "Ambient"
	particles.local_coords = true
	particles.layers = Layers.RENDER_FX
	particles.visibility_aabb = AABB(Vector3(-fluid_size.x * 0.5, -1.0, -fluid_size.z * 0.5), Vector3(fluid_size.x, 6.0, fluid_size.z))
	return particles

static func _noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.02
		_noise = NoiseTexture2D.new()
		_noise.noise = n
		_noise.seamless = true
		_noise.width = 256
		_noise.height = 256
		_noise.generate_mipmaps = true
	return _noise
