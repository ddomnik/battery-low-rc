class_name Effects
extends Node3D
## Cosmetic effects behind Match.play_effect (the single choke point that later becomes an RPC).
## Every effect is a short-lived node tree animated by its own Tween and freed when the tween ends.

const EXPLOSION_COLOR := Color(1.0, 0.55, 0.15)
const EXPLOSION_TIME := 0.4
const EXPLOSION_START_SCALE := 0.3
const EXPLOSION_ALPHA := 0.7
const POOF_COLOR := Color(1.0, 1.0, 1.0)
const FLASH_COLOR := Color(1.0, 0.85, 0.3)
const SPARK_COLOR := Color(1.0, 0.9, 0.4)
const RING_COLOR := Color(0.4, 0.95, 1.0)

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

func play(kind: StringName, pos: Vector3, param: float) -> void:
	match kind:
		&"explosion":
			_explosion(pos, param)
		&"pickup":
			_burst(pos, POOF_COLOR, 16, 3.0, 0.5, 0.18)
			_bubble(pos, POOF_COLOR, 0.4, 1.2, 0.25, 0.5)
		&"fire":
			_bubble(pos, FLASH_COLOR, 0.15, 0.45, 0.1, 0.9)
		&"bump":
			_burst(pos, SPARK_COLOR, 20, 9.0, 0.35, 0.1)
		&"landing":
			_ring(pos, 1.0, 3.0, 0.4)
		_:
			push_warning("Effects: unknown effect '%s'" % kind)

func _explosion(pos: Vector3, radius: float) -> void:
	_bubble(pos, EXPLOSION_COLOR, radius * EXPLOSION_START_SCALE, radius, EXPLOSION_TIME, EXPLOSION_ALPHA)
	_burst(pos, EXPLOSION_COLOR, 28, radius * 2.5, 0.7, 0.2)

## Expanding, fading unshaded sphere.
func _bubble(pos: Vector3, color: Color, start_radius: float, end_radius: float, time: float, alpha: float) -> void:
	var mat := _fade_material(color, alpha)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * start_radius
	var root := _root(pos)
	root.add_child(mi)
	var tw := root.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * end_radius, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(root.queue_free)

## Flat expanding ring on the ground.
func _ring(pos: Vector3, start_radius: float, end_radius: float, time: float) -> void:
	var mat := _fade_material(RING_COLOR, 0.8)
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
