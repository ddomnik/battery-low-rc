class_name Effects
extends Node3D
## Cosmetic effects behind Match.play_effect (the single choke point that later becomes an RPC).
## Every effect is a short-lived node tree animated by its own Tween and freed when the tween ends, plus a
## positional sound from Game.audio (variations rotate).

const EXPLOSION_COLOR := Color(1.0, 0.55, 0.15)
const EXPLOSION_TIME := 0.4
const EXPLOSION_START_SCALE := 0.3
const EXPLOSION_ALPHA := 0.7
const POOF_COLOR := Color(1.0, 1.0, 1.0)
const FLASH_COLOR := Color(1.0, 0.85, 0.3)
const SPARK_COLOR := Color(1.0, 0.9, 0.4)
const SHOCK_COLOR := Color(0.45, 0.85, 1.0)
const RING_COLOR := Color(0.4, 0.95, 1.0)
const SPLASH_COLOR := Color(0.35, 0.65, 1.0)
const DEBRIS_COLOR := Color(0.2, 0.2, 0.22)
const FIREWORK_LIGHT_ENERGY := 10.0
const FIREWORK_LIGHT_TIME := 0.5
const EXPLOSION_LIGHT_ENERGY := 8.0
const SPLASH_BUBBLE_ALPHA := 0.35
const PICKUP_COLORS := [Color("#FF595E"), Color("#FFCA3A"), Color("#8AC926"), Color("#1982C4"), Color("#FFFFFF")]
const DUST_PER_IMPACT := 0.4         # dust puffs per m/s of impact
const BALLOON_CONFETTI := 28         # flakes per popped balloon …
const BALLOON_CONFETTI_SPEED := 5.0
const BALLOON_CONFETTI_LIFETIME := 1.1
const BALLOON_CONFETTI_SCALE := Vector2(0.35, 0.6)   # … at this share of the full flake size
## Blast shells, inside out: color, start / end radius (× blast radius), time, alpha, delay.
const BLAST_LAYERS: Array[Array] = [
	[Color(1.0, 1.0, 0.9), 0.1, 0.45, 0.2, 0.9, 0.0],
	[Color(1.0, 0.85, 0.3), 0.15, 0.7, 0.3, 0.7, 0.03],
	[Color(1.0, 0.5, 0.15), 0.2, 0.95, 0.45, 0.5, 0.06],
	[Color(0.85, 0.25, 0.1), 0.3, 1.1, 0.6, 0.35, 0.1],
	[Color(0.4, 0.4, 0.42), 0.4, 1.3, 0.9, 0.25, 0.15],
]
const LOUD_IMPACT := 20.0            # bump strength / crash speed (m/s) that plays at full volume
const QUIET_IMPACT_GAIN := 0.35      # softest impact volume (linear)
const THROW_PITCH := 1.5             # balloon throw reuses the rocket launch sound, higher
const SHOCK_PITCH := 1.8
const SHOCK_FLASH_COLOR := Color(0.75, 0.93, 1.0)
const SHOCK_LIGHT_ENERGY := 12.0     # flash light at the Shocker user …
const SHOCK_HIT_LIGHT_ENERGY := 6.0  # … and at every shocked car
const SHOCK_HIT_LIGHT_RANGE := 5.0
const SHOCK_LIGHT_TIME := 0.35
const SHOCK_ARC_TIME := 0.6          # bolt from the user to each shocked car
const SHOCK_CRACKLES := 6            # short bolts from the user into the ground around it
const SHOCK_CRACKLE_TIME := 0.3
const SHOCK_CRACKLE_REACH := Vector2(0.3, 0.65)   # crackle length as a share of the Shocker reach
const SPLAT_PITCH := 0.7
const POP_PITCH := 1.6
const CONFETTI_SHADER: Shader = preload("res://match/confetti.gdshader")
const CONFETTI_MIN_SCALE := 0.5
const CONFETTI_BURST_RADIUS := 0.35  # balloon pop: flakes start anywhere in the balloon …
const CONFETTI_GRAVITY := 9.0        # … and fall properly, each with its own air drag
const CONFETTI_DRAG := Vector2(2.0, 6.0)

var _rng := RandomNumberGenerator.new()   # cosmetic only (crackle directions)

func _ready() -> void:
	_rng.randomize()

## A small unshaded box whose color comes from the particle color (vertex color), with alpha.
static func particle_mesh(size: float) -> BoxMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = mat
	return mesh

## from / to: nodes an effect follows (the Shocker bolts); see Match.play_effect.
func play(kind: StringName, pos: Vector3, param: float, color: Color = Color.WHITE, from: Node3D = null,
		to: Node3D = null) -> void:
	var audio := Game.audio
	match kind:
		&"confetti":    # balloon popping into confetti of its color
			_confetti(pos, color, BALLOON_CONFETTI, BALLOON_CONFETTI_SPEED, BALLOON_CONFETTI_LIFETIME, BALLOON_CONFETTI_SCALE)
			audio.play_at(&"splash", pos, 0.0, POP_PITCH)
		&"car_burst":   # sticky bomb victim breaking apart; color = the car's color
			_explosion(pos, 3.5, EXPLOSION_COLOR)
			_burst(pos, color, 40, 9.0, 1.1, 0.35)
			_burst(pos, Color(0.15, 0.15, 0.18), 20, 7.0, 1.0, 0.25)
			ParticleFx.blast(self, pos, 3.5, color)
			_light(pos + Vector3.UP, EXPLOSION_COLOR, EXPLOSION_LIGHT_ENERGY, 10.0, 0.4)
			audio.play_at(&"explosion", pos)
		&"firework":    # firework rocket: random shell, palette and size; param = radius
			var main := ParticleFx.firework(self, pos, param, _rng)
			_light(pos, main, FIREWORK_LIGHT_ENERGY, param * 3.0, FIREWORK_LIGHT_TIME)
			_bubble(pos, Color.WHITE, param * 0.1, param * 0.45, 0.12, 0.9, true)
			audio.play_at(&"explosion", pos, 0.0, _rng.randf_range(0.9, 1.2))
		&"explosion":   # Blast, sticky bomb: layered see-through fire shells, no particles; param = radius
			for layer in BLAST_LAYERS:
				_bubble(pos, layer[0], param * layer[1], param * layer[2], layer[3], layer[4], false, layer[5])
			_light(pos + Vector3.UP, EXPLOSION_COLOR, EXPLOSION_LIGHT_ENERGY, param * 2.5, 0.4)
			audio.play_at(&"explosion", pos)
		&"splash":      # water balloon; param = radius
			_bubble(pos, SPLASH_COLOR, param * EXPLOSION_START_SCALE, param, EXPLOSION_TIME, SPLASH_BUBBLE_ALPHA)
			ParticleFx.water(self, pos, param, SPLASH_COLOR)
			_ring(pos + Vector3.DOWN * 0.3, 0.5, param * 1.2, 0.5, SPLASH_COLOR.lightened(0.4))
			audio.play_at(&"splash", pos)
		&"pickup":
			_burst(pos, POOF_COLOR, 16, 3.0, 0.5, 0.18)
			_bubble(pos, POOF_COLOR, 0.4, 1.2, 0.25, 0.5)
			ParticleFx.sparks(self, pos, PackedColorArray(PICKUP_COLORS), 36, 6.0, 0.8)
			audio.play_at(&"pickup", pos)
		&"fire":        # rocket launch
			_bubble(pos, FLASH_COLOR, 0.15, 0.45, 0.1, 0.9)
			ParticleFx.sparks(self, pos, PackedColorArray([SPARK_COLOR]), 20, 4.0, 0.4)
			ParticleFx.smoke(self, pos, 5, 0.8, 0.6, Vector2(0.3, 1.0))
			audio.play_at(&"launch", pos)
		&"throw":       # water balloon / oil / glue launch
			_bubble(pos, SPLASH_COLOR, 0.15, 0.4, 0.1, 0.7)
			ParticleFx.smoke(self, pos, 4, 0.6, 0.5, Vector2(0.3, 0.8))
			audio.play_at(&"launch", pos, 0.0, THROW_PITCH)
		&"shock":       # Shocker activated; param = reach, from = the user
			_light(pos + Vector3.UP, SHOCK_FLASH_COLOR, SHOCK_LIGHT_ENERGY, param * 1.5, SHOCK_LIGHT_TIME)
			_bubble(pos, SHOCK_FLASH_COLOR, 0.5, 3.0, 0.18, 1.0, true)
			_ring(pos + Vector3.DOWN * 0.5, 1.0, param, 0.35, SHOCK_COLOR)
			_burst(pos, SHOCK_COLOR, 40, 12.0, 0.45, 0.08)
			for i in SHOCK_CRACKLES:
				var angle := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / SHOCK_CRACKLES
				var reach := param * _rng.randf_range(SHOCK_CRACKLE_REACH.x, SHOCK_CRACKLE_REACH.y)
				var end := pos + Vector3(sin(angle), 0.0, cos(angle)) * reach + Vector3.DOWN * 0.3
				_arc(from, null, pos + Vector3.UP * ShockArc.LIFT, end, SHOCK_CRACKLE_TIME)
			audio.play_at(&"pickup", pos, 0.0, SHOCK_PITCH)
		&"shock_arc":   # electric bolt from the Shocker user (from) to a shocked car (to, at pos)
			_arc(from, to, pos + Vector3.UP * ShockArc.LIFT, pos + Vector3.UP * ShockArc.LIFT, SHOCK_ARC_TIME)
			_light(pos + Vector3.UP, SHOCK_FLASH_COLOR, SHOCK_HIT_LIGHT_ENERGY, SHOCK_HIT_LIGHT_RANGE, SHOCK_LIGHT_TIME)
			_bubble(pos, SHOCK_FLASH_COLOR, 0.3, 1.6, 0.15, 1.0, true)
			_burst(pos, SHOCK_COLOR, 20, 5.0, 0.5, 0.07)
		&"fluid_splash":   # a car drives into a fluid; param = speed, color = the fluid's color
			var r := clampf(param * 0.25, 1.2, 4.0)
			ParticleFx.water(self, pos + Vector3.UP * 0.1, r, color)
			_ring(pos + Vector3.UP * 0.05, 0.4, r * 1.2, 0.5, color.lightened(0.3))
			audio.play_at(&"splash", pos, _impact_db(param))
		&"splat":       # oil / glue puddle appears; param = radius
			_burst(pos + Vector3.UP * 0.2, color, 24, 4.0, 0.5, 0.18)
			ParticleFx.water(self, pos + Vector3.UP * 0.2, param * 0.6, color, false)
			audio.play_at(&"splash", pos, 0.0, SPLAT_PITCH)
		&"bump":        # car on car; param = bump strength
			_burst(pos, SPARK_COLOR, 20, 9.0, 0.35, 0.1)
			ParticleFx.streaks(self, pos, SPARK_COLOR, 24, 10.0, 0.4)
			ParticleFx.dust(self, pos + Vector3.DOWN * 0.4, clampi(int(param * DUST_PER_IMPACT), 2, 10), 1.0)
			audio.play_at(&"bump", pos, _impact_db(param))
		&"wall":        # car into a wall; param = impact speed
			_burst(pos, SPARK_COLOR, 20, 9.0, 0.35, 0.1)
			ParticleFx.streaks(self, pos, SPARK_COLOR, 30, 11.0, 0.45)
			ParticleFx.dust(self, pos + Vector3.DOWN * 0.4, clampi(int(param * DUST_PER_IMPACT), 2, 10), 1.2)
			audio.play_at(&"wall", pos, _impact_db(param))
		&"pop":         # balloon popped / car eliminated
			_burst(pos, POOF_COLOR, 24, 6.0, 0.5, 0.15)
			_bubble(pos, POOF_COLOR, 0.2, 1.0, 0.15, 0.7)
			ParticleFx.sparks(self, pos, PackedColorArray([Color.WHITE]), 30, 6.0, 0.6)
			audio.play_at(&"splash", pos, 0.0, POP_PITCH)
		&"landing":     # perfect landing
			_ring(pos, 1.0, 3.0, 0.4, RING_COLOR)
			ParticleFx.sparks(self, pos + Vector3.UP * 0.3, PackedColorArray([RING_COLOR, Color.WHITE]), 40, 5.0, 0.7)
			audio.play_at(&"perfect_landing", pos)
		_:
			push_warning("Effects: unknown effect '%s'" % kind)

## Harder impacts are louder.
func _impact_db(strength: float) -> float:
	return linear_to_db(clampf(strength / LOUD_IMPACT, QUIET_IMPACT_GAIN, 1.0))

func _explosion(pos: Vector3, radius: float, color: Color) -> void:
	_bubble(pos, color, radius * EXPLOSION_START_SCALE, radius, EXPLOSION_TIME, EXPLOSION_ALPHA)
	_burst(pos, color, 28, radius * 2.5, 0.7, 0.2)

## Expanding, fading unshaded sphere. additive = glowing flash. delay: s before it appears.
func _bubble(pos: Vector3, color: Color, start_radius: float, end_radius: float, time: float, alpha: float,
		additive: bool = false, delay: float = 0.0) -> void:
	var mat := _fade_material(color, alpha)
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * start_radius
	mi.visible = delay <= 0.0
	var root := _root(pos)
	root.add_child(mi)
	var tw := root.create_tween().set_parallel()
	if delay > 0.0:
		tw.tween_callback(mi.show).set_delay(delay)
	tw.tween_property(mi, "scale", Vector3.ONE * end_radius, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC) \
		.set_delay(delay)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_delay(delay)
	tw.chain().tween_callback(root.queue_free)

## Short bright light that dies away (flashes light up the ground and the cars around).
func _light(pos: Vector3, color: Color, energy: float, light_range: float, time: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	var root := _root(pos)
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(root.queue_free)

## Crackling electric bolt; follows the nodes while they exist, else the fixed points.
func _arc(from: Node3D, to: Node3D, from_point: Vector3, to_point: Vector3, time: float) -> void:
	var arc := ShockArc.new()
	arc.from_node = from
	arc.to_node = to
	arc.from_point = from_point
	arc.to_point = to_point
	arc.duration = time
	add_child(arc)

## Flat expanding ring on the ground.
func _ring(pos: Vector3, start_radius: float, end_radius: float, time: float, color: Color) -> void:
	var mat := _fade_material(color, 0.8)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(start_radius, 0.05, start_radius)
	var root := _root(pos + Vector3.UP * 0.05)
	root.add_child(mi)
	var tw := root.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(end_radius, 0.05, end_radius), time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(root.queue_free)

## Paper confetti: flat flakes that tumble and flutter down. A white color means every color.
func _confetti(pos: Vector3, color: Color, amount: int, speed: float, lifetime: float,
		scale_range: Vector2 = Vector2(CONFETTI_MIN_SCALE, 1.0)) -> void:
	var p := confetti_particles(color)
	p.scale_amount_min = scale_range.x
	p.scale_amount_max = scale_range.y
	p.one_shot = true
	p.explosiveness = 0.9
	p.randomness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.lifetime_randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = CONFETTI_BURST_RADIUS
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.15
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -CONFETTI_GRAVITY, 0.0)
	p.damping_min = CONFETTI_DRAG.x
	p.damping_max = CONFETTI_DRAG.y
	var root := _root(pos)
	root.add_child(p)
	p.emitting = true
	root.create_tween().tween_callback(root.queue_free).set_delay(lifetime + 0.1)

## Shared confetti look (also used by the podium): small flat flakes tumbling in all directions (shader), slow fall.
static func confetti_particles(color: Color) -> CPUParticles3D:
	var mat := ShaderMaterial.new()
	mat.shader = CONFETTI_SHADER
	var flake := BoxMesh.new()
	flake.size = Vector3(0.28, 0.01, 0.18)
	flake.material = mat
	var p := CPUParticles3D.new()
	p.mesh = flake
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # shadows read as dark specks from above
	p.scale_amount_min = CONFETTI_MIN_SCALE   # flakes from half size …
	p.scale_amount_max = 1.0                  # … to full size
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	var colors := Gradient.new()
	if color == Color.WHITE:
		colors.colors = PackedColorArray([Color("#FF595E"), Color("#FFCA3A"), Color("#8AC926"), Color("#1982C4"), Color("#6A4C93"), Color("#FF924C"), Color("#4CC9F0")])
		colors.offsets = PackedFloat32Array([0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0])
		colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	else:
		colors.colors = PackedColorArray([color.darkened(0.25), color, color.lightened(0.35)])
		colors.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_initial_ramp = colors
	return p

## One-shot particle burst in all directions.
func _burst(pos: Vector3, color: Color, amount: int, speed: float, lifetime: float, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -15.0, 0.0)
	p.mesh = particle_mesh(size)
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	var root := _root(pos)
	root.add_child(p)
	p.emitting = true
	root.create_tween().tween_callback(root.queue_free).set_delay(lifetime + 0.1)

func _root(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # animated per frame by tweens
	root.position = pos
	add_child(root)
	return root

func _fade_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
