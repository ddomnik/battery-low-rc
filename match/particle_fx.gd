class_name ParticleFx
## Particle building blocks for Effects, the rocket trail and car visuals: sparks, streaks, smoke, droplets,
## dust and firework bursts. Every builder adds a CPUParticles3D (world-space particles) to the given parent
## and returns it. One-shot systems free themselves once their particles are gone. Cosmetic only.
## Note: a CPUParticles3D must be fully configured BEFORE it enters the tree — velocity / spread set afterwards
## are ignored (every particle stays at the emitter). So builders configure first and _launch() last.

enum Shell { PEONY, RING, DOUBLE_RING, WILLOW, CHRYSANTHEMUM }

const WILLOW_GOLD := Color("#FFC94A")
const GLITTER_COLOR := Color(1.0, 0.97, 0.85)
const SMOKE_COLOR := Color(0.55, 0.55, 0.58, 0.55)
const DUST_COLOR := Color(0.82, 0.76, 0.66, 0.6)
const SPARK_SIZE := 0.26                  # sized for the ~50 m camera
const STREAK_SIZE := Vector3(0.1, 0.6, 0.1)
const FREE_MARGIN := 0.2                  # s after the last particle dies
const STAR_WIDTH := 0.46                  # firework star tail width at the head (m) …
const STAR_TRAIL := 0.35                  # … and length in seconds of flight
const STAR_TRAIL_SECTIONS := 10
const STAR_SPEED := 3.3                   # star launch speed per m of shell size (fast burst) …
const STAR_DRAG := 0.85                   # … and air drag as a share of it per second
const ASH_STARS := Vector2i(4, 7)         # every shell also throws a few grey stars …
const ASH_COLOR := Color(0.5, 0.5, 0.52)  # … this grey
const FUSE_SMOKE := Color(0.42, 0.42, 0.45, 0.7)
const FUSE_SPARKS: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.55), Color(1.0, 0.55, 0.15), Color(0.9, 0.3, 0.05, 0.0)]

static var _soft_dot: GradientTexture2D = null

# --- Firework ----------------------------------------------------------------------------------------

static func firework_palettes() -> Array[PackedColorArray]:
	return [
		PackedColorArray([Color("#FF3B3B"), Color("#FFD23F")]),
		PackedColorArray([Color("#3BCBFF"), Color("#FFFFFF")]),
		PackedColorArray([Color("#FF4FD8"), Color("#9B5CFF")]),
		PackedColorArray([Color("#5CFF6A"), Color("#E8FF5C")]),
		PackedColorArray([Color("#FF8A1F"), Color("#FFE45C")]),
		PackedColorArray([Color("#4F7BFF"), Color("#C8D8FF")]),
		PackedColorArray([Color("#FF595E"), Color("#FFCA3A"), Color("#8AC926"), Color("#1982C4"), Color("#6A4C93")]),
	]

## A random firework shell bursting at pos: about 20 stars, each pulling a tail like a shooting star.
## Random shape, palette and size; radius ≈ the explosion radius. Returns the main color (for the flash light).
static func firework(parent: Node3D, pos: Vector3, radius: float, rng: RandomNumberGenerator) -> Color:
	var palettes := firework_palettes()
	var palette := palettes[rng.randi() % palettes.size()]
	var first := PackedColorArray([palette[0]])
	var last := PackedColorArray([palette[palette.size() - 1]])
	var shell := (rng.randi() % Shell.size()) as Shell
	var size := radius * rng.randf_range(0.95, 1.7)
	match shell:
		Shell.PEONY:
			_stars(parent, pos, palette, rng.randi_range(26, 34), size, 1.4, STAR_TRAIL, -4.0, 0.0, Basis.IDENTITY)
		Shell.CHRYSANTHEMUM:   # every star its own color, longer tails
			_stars(parent, pos, palette, 36, size * 1.1, 1.5, STAR_TRAIL * 1.4, -4.0, 0.0, Basis.IDENTITY, true)
		Shell.RING:
			_stars(parent, pos, palette, 28, size, 1.3, STAR_TRAIL, -3.0, 1.0, _random_tilt(rng))
		Shell.DOUBLE_RING:
			_stars(parent, pos, first, 17, size, 1.3, STAR_TRAIL, -3.0, 1.0, _random_tilt(rng))
			_stars(parent, pos, last, 17, size * 0.75, 1.3, STAR_TRAIL, -3.0, 1.0, _random_tilt(rng))
		Shell.WILLOW:   # long gold tails that droop
			_stars(parent, pos, PackedColorArray([WILLOW_GOLD, palette[0]]), 30, size * 0.9, 2.2, STAR_TRAIL * 2.6, -9.0, 0.0,
				Basis.IDENTITY)
	_stars(parent, pos, PackedColorArray([ASH_COLOR]), rng.randi_range(ASH_STARS.x, ASH_STARS.y), size * 0.8, 1.2,
		STAR_TRAIL, -5.0, 0.0, Basis.IDENTITY)
	glitter(parent, pos, size * 0.7, 0.45)
	smoke(parent, pos, 4, 1.4, 1.8, Vector2(0.3, 1.0))
	return palette[0]

## Stars flying out from the center, each with a tapering tail (GPU particle trails).
## flatness 1 = a flat ring (in the tilt's XZ plane). mixed = a random palette color per star.
static func _stars(parent: Node3D, pos: Vector3, colors: PackedColorArray, amount: int, size: float, lifetime: float,
		trail: float, gravity: float, flatness: float, tilt: Basis, mixed: bool = false) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.RIGHT if flatness > 0.0 else Vector3.UP
	pm.spread = 180.0
	pm.flatness = flatness
	var speed := size * STAR_SPEED
	pm.initial_velocity_min = speed * 0.85
	pm.initial_velocity_max = speed
	pm.damping_min = speed * STAR_DRAG   # air drag: the stars slow down near the shell's size, then sink
	pm.damping_max = speed * STAR_DRAG * 1.2
	pm.gravity = Vector3(0.0, gravity, 0.0)
	var end := colors[colors.size() - 1]
	if mixed or colors.size() > 2:
		pm.color_initial_ramp = _texture(_steps(colors))
		pm.color_ramp = _texture(gradient(PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])))
	else:   # a white flash, then the full colors quickly (pale otherwise)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.65, 1.0])
		g.colors = PackedColorArray([Color.WHITE, colors[0], end, Color(end, 0.0)])
		pm.color_ramp = _texture(g)
	var p := GPUParticles3D.new()
	p.process_material = pm
	p.draw_pass_1 = _star_trail_mesh()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.trail_enabled = true
	p.trail_lifetime = trail
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3.ONE * -size * 2.5, Vector3.ONE * size * 5.0)
	var holder := Node3D.new()
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	holder.add_child(p)
	parent.add_child(holder)
	holder.global_transform = Transform3D(tilt, pos)
	p.finished.connect(holder.queue_free)
	p.emitting = true
	return p

## Crossed ribbons along a star's path, full width at the star, thinning to nothing at the end of the tail.
static func _star_trail_mesh() -> RibbonTrailMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.use_particle_trails = true
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var m := RibbonTrailMesh.new()
	m.shape = RibbonTrailMesh.SHAPE_CROSS
	m.size = STAR_WIDTH
	m.sections = STAR_TRAIL_SECTIONS
	m.curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])   # section 0 is the star's end: fat head, thin tail
	m.material = mat
	return m

static func _texture(g: Gradient) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## Streaks flying out from the center: a shell. flatness 1 = a flat ring (in the tilt's XZ plane).
static func _shell(parent: Node3D, pos: Vector3, colors: PackedColorArray, size: float, amount: int, flatness: float,
		tilt: Basis, lifetime: float, gravity: float, mixed: bool = false) -> CPUParticles3D:
	var p := _one_shot(streak_mesh(), amount, lifetime)
	p.direction = Vector3.RIGHT if flatness > 0.0 else Vector3.UP
	p.spread = 180.0
	p.flatness = flatness
	var speed := size * 2.6
	p.initial_velocity_min = speed * 0.85
	p.initial_velocity_max = speed
	p.damping_min = speed * 1.1   # air drag: the shell stops at about its size, then sinks
	p.damping_max = speed * 1.4
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _curve([Vector2(0.0, 1.0), Vector2(0.7, 0.8), Vector2(1.0, 0.0)])
	p.lifetime_randomness = 0.3
	if mixed or colors.size() > 2:
		p.color_initial_ramp = _steps(colors)
		p.color_ramp = gradient(PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)]))
	else:
		var end := colors[colors.size() - 1]
		p.color_ramp = gradient(PackedColorArray([Color.WHITE, colors[0], end, Color(end, 0.0)]))
	return _launch(parent, pos, p, tilt)

## Twinkling white sparkles spread through a sphere, after a short delay.
static func glitter(parent: Node3D, pos: Vector3, radius: float, delay: float) -> void:
	var p := _one_shot(spark_mesh(SPARK_SIZE * 0.6), 70, 0.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.explosiveness = 0.6
	p.gravity = Vector3(0.0, -2.0, 0.0)
	p.color_ramp = gradient(PackedColorArray([Color(GLITTER_COLOR, 0.0), GLITTER_COLOR, Color(GLITTER_COLOR, 0.0),
		GLITTER_COLOR, Color(GLITTER_COLOR, 0.0)]))
	_launch(parent, pos, p, Basis.IDENTITY, false)
	# Bound to the node's own method: the connection goes away if the node is freed first (match left).
	parent.get_tree().create_timer(delay).timeout.connect(p.set_emitting.bind(true))

## Grey smoke and orange / white sparks spitting out of a flying firework rocket's fuse end (continuous; stop
## and free it with release()). GPU particles: continuous CPU billboard emitters draw a black blob at the emitter.
static func rocket_trail(parent: Node3D, offset: Vector3) -> Array[GPUParticles3D]:
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.BACK
	spm.spread = 25.0
	spm.initial_velocity_min = 1.0
	spm.initial_velocity_max = 3.5
	spm.gravity = Vector3(0.0, -5.0, 0.0)
	spm.scale_min = 0.4
	spm.scale_max = 1.2
	spm.lifetime_randomness = 0.4
	spm.color_ramp = _texture(gradient(PackedColorArray(FUSE_SPARKS)))
	var sparks := continuous(spm, spark_mesh(SPARK_SIZE), 90, 0.7)
	sparks.position = offset
	var mpm := ParticleProcessMaterial.new()
	mpm.direction = Vector3.BACK
	mpm.spread = 10.0
	mpm.initial_velocity_min = 0.2
	mpm.initial_velocity_max = 0.6
	mpm.gravity = Vector3(0.0, 0.4, 0.0)
	var grow := CurveTexture.new()
	grow.curve = _curve([Vector2(0.0, 0.4), Vector2(1.0, 1.0)])
	mpm.scale_curve = grow
	mpm.scale_min = 1.0
	mpm.scale_max = 1.6
	mpm.color_ramp = _texture(gradient(PackedColorArray([Color(FUSE_SMOKE, 0.3), FUSE_SMOKE, Color(FUSE_SMOKE, 0.0)])))
	var smoke_trail := continuous(mpm, smoke_mesh(0.55), 50, 1.1)
	smoke_trail.position = offset
	parent.add_child(sparks)
	parent.add_child(smoke_trail)
	return [sparks, smoke_trail]

## A continuously emitting world-space GPU particle system (not yet in the tree).
static func continuous(pm: ParticleProcessMaterial, mesh: Mesh, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Detach continuous particles into new_parent (keeping their world position), stop them, free them later.
static func release(systems: Array[GPUParticles3D], new_parent: Node) -> void:
	for p in systems:
		if not is_instance_valid(p):
			continue
		p.reparent(new_parent, true)
		p.emitting = false
		p.get_tree().create_timer(p.lifetime + FREE_MARGIN).timeout.connect(p.queue_free)

# --- Explosions, water, dust ----------------------------------------------------------------------------

## Fire sparks, debris and rising smoke (Blast, sticky bomb, car burst).
static func blast(parent: Node3D, pos: Vector3, radius: float, debris_color: Color) -> void:
	var fire := _one_shot(streak_mesh(), 70, 0.7)
	fire.spread = 180.0
	fire.initial_velocity_min = radius * 2.0
	fire.initial_velocity_max = radius * 4.0
	fire.damping_min = radius * 3.0
	fire.damping_max = radius * 5.0
	fire.gravity = Vector3(0.0, -6.0, 0.0)
	fire.particle_flag_align_y = true
	fire.lifetime_randomness = 0.4
	fire.color_ramp = gradient(PackedColorArray([Color.WHITE, Color("#FFD23F"), Color("#FF6A1F"), Color(0.6, 0.1, 0.05, 0.0)]))
	_launch(parent, pos, fire)
	var debris := _one_shot(chunk_mesh(0.18), 24, 1.3)
	debris.spread = 70.0
	debris.direction = Vector3.UP
	debris.initial_velocity_min = radius * 1.0
	debris.initial_velocity_max = radius * 2.2
	debris.gravity = Vector3(0.0, -18.0, 0.0)
	debris.angular_velocity_min = -720.0
	debris.angular_velocity_max = 720.0
	debris.scale_amount_min = 0.5
	debris.scale_amount_max = 1.5
	debris.color = debris_color
	_launch(parent, pos, debris)
	smoke(parent, pos, 12, 2.2, 2.0, Vector2(0.6, 1.8))

## Water balloon (or oil / glue splat): lots of droplets, a spray column and (water only) mist.
static func water(parent: Node3D, pos: Vector3, radius: float, color: Color, with_mist: bool = true) -> void:
	var drops := _one_shot(drop_mesh(0.1), 140, 1.1)
	drops.direction = Vector3.UP
	drops.spread = 85.0
	drops.initial_velocity_min = radius * 0.6
	drops.initial_velocity_max = radius * 2.6
	drops.gravity = Vector3(0.0, -18.0, 0.0)
	drops.scale_amount_min = 0.4
	drops.scale_amount_max = 1.6
	drops.lifetime_randomness = 0.3
	drops.color_initial_ramp = gradient(PackedColorArray([color.lightened(0.5), color, color.darkened(0.15)]))
	_launch(parent, pos, drops)
	var column := _one_shot(drop_mesh(0.07), 60, 0.9)
	column.direction = Vector3.UP
	column.spread = 18.0
	column.initial_velocity_min = radius * 1.5
	column.initial_velocity_max = radius * 3.0
	column.gravity = Vector3(0.0, -18.0, 0.0)
	column.color = color.lightened(0.6) if with_mist else color
	_launch(parent, pos, column)
	if with_mist:
		var mist_color := color.lightened(0.7)
		_launch(parent, pos, _smoke_system(10, 1.6, 1.0, Vector2(0.8, 2.0),
			PackedColorArray([Color(mist_color, 0.0), Color(mist_color, 0.5), Color(mist_color, 0.0)])))

## Soft puffs drifting up and growing.
static func smoke(parent: Node3D, pos: Vector3, amount: int, lifetime: float, size: float, speed: Vector2) -> CPUParticles3D:
	return _launch(parent, pos, _smoke_system(amount, lifetime, size, speed,
		PackedColorArray([Color(SMOKE_COLOR, 0.0), SMOKE_COLOR, Color(SMOKE_COLOR, 0.0)])))

## Dust kicked up along the ground (landings, crashes).
static func dust(parent: Node3D, pos: Vector3, amount: int, size: float) -> CPUParticles3D:
	var p := _smoke_system(amount, 1.0, size, Vector2(1.0, 3.0),
		PackedColorArray([Color(DUST_COLOR, 0.0), DUST_COLOR, Color(DUST_COLOR, 0.0)]))
	p.spread = 85.0
	p.flatness = 0.7
	return _launch(parent, pos, p)

## Bright sparks in all directions (impacts, pickups). Several colors = a random one per spark.
static func sparks(parent: Node3D, pos: Vector3, colors: PackedColorArray, amount: int, speed: float, lifetime: float) -> CPUParticles3D:
	var p := _one_shot(spark_mesh(SPARK_SIZE), amount, lifetime)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	p.lifetime_randomness = 0.4
	if colors.size() > 1:
		p.color_initial_ramp = _steps(colors)
		p.color_ramp = gradient(PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)]))
	else:
		p.color_ramp = gradient(PackedColorArray([Color.WHITE, colors[0], Color(colors[0], 0.0)]))
	return _launch(parent, pos, p)

## Glowing streaks along their flight (impact sparks).
static func streaks(parent: Node3D, pos: Vector3, color: Color, amount: int, speed: float, lifetime: float) -> CPUParticles3D:
	var p := _one_shot(streak_mesh(), amount, lifetime)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -14.0, 0.0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color_ramp = gradient(PackedColorArray([Color.WHITE, color, Color(color, 0.0)]))
	return _launch(parent, pos, p)

static func _smoke_system(amount: int, lifetime: float, size: float, speed: Vector2, colors: PackedColorArray) -> CPUParticles3D:
	var p := _one_shot(smoke_mesh(size * 0.6), amount, lifetime)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.3
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.damping_min = speed.y * 0.5
	p.damping_max = speed.y
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _curve([Vector2(0.0, 0.5), Vector2(1.0, 1.6)])
	p.lifetime_randomness = 0.3
	p.color_ramp = gradient(colors)
	return p

# --- Meshes and helpers ---------------------------------------------------------------------------------

## Soft round billboard dot (sparks): unshaded, colored by the particle color (sRGB).
static func spark_mesh(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = _billboard_material()
	return q

## Soft round billboard puff (smoke, mist, dust).
static func smoke_mesh(size: float) -> QuadMesh:
	return spark_mesh(size)

## Glowing stick that lines up with the particle's velocity (use particle_flag_align_y).
static func streak_mesh() -> BoxMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var m := BoxMesh.new()
	m.size = STREAK_SIZE
	m.material = mat
	return m

## Glossy droplet (water).
static func drop_mesh(radius: float) -> SphereMesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.1
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	m.material = mat
	return m

## Small solid chunk (debris).
static func chunk_mesh(size: float) -> BoxMesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = mat
	return m

static func gradient(colors: PackedColorArray) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / maxf(colors.size() - 1, 1.0))
	g.offsets = offsets
	g.colors = colors
	return g

## A one-shot burst, not yet in the tree: configure it, then _launch() it.
static func _one_shot(mesh: Mesh, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Adds a configured one-shot in its own holder at pos (turned by tilt) and starts it (unless start is false);
## both free themselves when the particles are done.
static func _launch(parent: Node3D, pos: Vector3, p: CPUParticles3D, tilt: Basis = Basis.IDENTITY,
		start: bool = true) -> CPUParticles3D:
	var holder := Node3D.new()
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	holder.add_child(p)
	parent.add_child(holder)
	holder.global_transform = Transform3D(tilt, pos)
	p.finished.connect(holder.queue_free)
	p.emitting = start
	return p

static func _billboard_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = soft_dot()
	return mat

static func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		g.add_point(0.45, Color(1.0, 1.0, 1.0, 0.85))
		_soft_dot = GradientTexture2D.new()
		_soft_dot.gradient = g
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(0.5, 0.0)
		_soft_dot.width = 32
		_soft_dot.height = 32
	return _soft_dot

## Hard color steps (random pick per particle from color_initial_ramp).
static func _steps(colors: PackedColorArray) -> Gradient:
	var g := gradient(colors)
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	return g

static func _curve(points: Array[Vector2]) -> Curve:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	return c

static func _random_tilt(rng: RandomNumberGenerator) -> Basis:
	return Basis(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)).normalized(),
		rng.randf_range(0.3, 1.3))
