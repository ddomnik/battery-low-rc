class_name CarVisual
extends Node3D
## Cosmetic side of a car: Kenney model, animated wheels, held item model, name label, blob shadow.
## Reads car state only; never changes gameplay.

const MODEL_DIR := "res://assets/kenney_car_kit/"
## The local player gets the first of these that exists.
const PLAYER_MODELS: Array[String] = ["race", "race-future", "sedan-sports"]
## Bots cycle through these so cars are easy to tell apart (all have exactly four wheel nodes).
const BOT_MODELS: Array[String] = ["race-future", "sedan-sports", "hatchback-sports", "police", "race"]

const STEER_VISUAL_ANGLE := 0.5 # front-wheel turn (rad) at full steer
const STEER_SHARPNESS := 12.0
const SUSPENSION_VISUAL_SCALE := 0.5 # wheels show this share of the physics spring travel …
const SUSPENSION_VISUAL_UP := 0.06 # … at most this far up into the body …
const SUSPENSION_VISUAL_DOWN := 0.1 # … and this far down
const SUSPENSION_VISUAL_SHARPNESS := 25.0 # smoothing
const LABEL_HEIGHT := -1.8
const LABEL_FONT_SIZE := 32
const LABEL_OUTLINE_SIZE := 10
const LABEL_PIXEL_SIZE := 0.0004 # fixed_size labels: world units per pixel at 1 m from the camera
const ITEM_AIM_SHARPNESS := 12.0 # held item model turning toward the reticle
const ITEM_POP_TIME := 0.25 # held item model pops in
const DEFAULT_ROOF_Y := 0.25 # item mount height when no model is loaded (chassis box top)
const SMOKE_COLOR := Color(0.9, 0.9, 0.9, 0.55)
const SMOKE_SIZE := 0.7
const SMOKE_LIFT := 0.1 # above the ground under the rear wheels
const EXHAUST_SHADER: Shader = preload("res://car/exhaust.gdshader")
const XRAY_SHADER: Shader = preload("res://car/xray.gdshader")
const XRAY_ALPHA := 0.55
const FLAME_COLOR := Color(0.55, 0.8, 1.0) # blue sparks streaming out of the exhaust
const FLAME_FADE_COLOR := Color(0.15, 0.3, 1.0, 0.0)
const FLAME_SIZE := 0.3
const FLAME_OFFSET := Vector3(0.0, -0.15, 1.05) # rear center, car-local
const EXHAUST_OUTER := Vector2(0.24, 1.4) # cone base radius, length
const EXHAUST_OUTER_COLOR := Color(0.25, 0.5, 1.0)
const EXHAUST_CORE := Vector2(0.11, 0.8)
const EXHAUST_CORE_COLOR := Color(0.7, 0.9, 1.0)
const EXHAUST_FADE_SPEED := 10.0 # cone grows / shrinks this fast (per second) when boost starts / stops
const EXHAUST_FLICKER_SPEED := 37.0
const EXHAUST_FLICKER := 0.15
const SPLATTER_DROP_RADIUS := 0.06
const SPLATTER_DROP_STRETCH := 2.2 # drops are stretched along their flight
const SPLATTER_AMOUNT := 64
const SPLATTER_LIFETIME := 0.8
const SPLATTER_DRIP_RATIO := 0.12 # share of drops a coated wheel still sheds at standstill …
const SPLATTER_DRIP_SPEED := 0.4 # … and how fast they leave the tire (m/s)
const SPLATTER_FLING_SPEED := 8.0 # fastest drop speed at top speed (each drop gets 30–100 %)
const SPLATTER_RISE := 0.7 # upward part of the fling direction (backward part is 1)
const SPLATTER_SPREAD := 45.0 # degrees
const SPLATTER_GRAVITY := 18.0
const SPLASH_DROPLETS := 4 # a drop hitting the ground bursts into this many droplets …
const SPLASH_DROPLET_RADIUS := 0.03 # … this small, which settle on the surface
const SPLASH_AMOUNT := 384
const SPLASH_LIFETIME := 1.4
const SPLASH_SPEED_MIN := 0.6
const SPLASH_SPEED_MAX := 2.2
const SPLASH_SPREAD := 75.0
const SPLASH_BOUNCE := 0.15
const SHADOW_SIZE := Vector3(1.6, 12.0, 2.4)
const ENGINE_PITCH_IDLE := 0.8 # engine pitch at standstill …
const ENGINE_PITCH_TOP := 1.6 # … and at boost top speed
const AIR_PITCH_EXTRA := 0.25 # the airborne motor revs a bit higher on top
const ENGINE_DB_LOCAL := -6.0 # your car
const ENGINE_DB_OTHER := -15.0 # everyone else (ten engines at once get loud)
const ENGINE_FADE := 8.0 # 1/s; ground ↔ air engine cross-fade
const BOOST_DB := -4.0
const DRIFT_DB := -8.0
const SOUND_UNIT_SIZE := 30.0 # the camera listens from ~50 m away
const SILENT_DB := -60.0
const SHADOW_TOP := 2.0 # the decal box spans 2 m above to 10 m below the car
const SHADOW_ALPHA := 0.55
const SHADOW_TEXTURE_SIZE := 64

@export var model_yaw_deg: float = 180.0 # glTF models face +Z, our forward is −Z
@export var visual_length: float = 2.0

var car: Car = null
## Car-local mount point of the held item's model (top center of the car); Car.get_muzzle_position builds on it.
var item_mount: Vector3 = Vector3(0.0, DEFAULT_ROOF_Y, 0.0)
## The held item model's muzzle (null without an item or without a Muzzle marker); cosmetic aim lines start here.
var muzzle: Node3D = null

var _item_pivot: Node3D = null # turns toward the aim for aimed items
var _item_model: Node3D = null
var _item: ItemDef = null
var _model: Node3D = null
var _model_base: Transform3D = Transform3D.IDENTITY
## Cosmetic roll of the chassis (model body + held item) around the car's length axis; wheels stay put.
var body_roll: float = 0.0
## Silences engine, boost and drift sounds (podium ceremony).
var mute_engine: bool = false
var _wheels: Array[Node3D] = []
var _wheel_basis: Array[Basis] = []
var _wheel_angle: Array[float] = []
var _pivots: Array[Node3D] = []
var _pivot_base: Array[Vector3] = []
var _wheel_spin_sign: float = 1.0
var _visual_wheel_radius: float = 0.3
var _rest_spring: float = 0.0 # rest length minus sag
var _wheel_offset: Array[float] = [0.0, 0.0, 0.0, 0.0] # shown suspension travel per wheel (+ = up)
var _base_color: Color = Color.WHITE
var _is_local: bool = false
var _shadow: Decal = null
var _label: Label3D = null
var _smoke: Array[GPUParticles3D] = []
var _flame: GPUParticles3D = null
var _exhaust: Node3D = null
var _exhaust_mats: Array[ShaderMaterial] = []
var _exhaust_amount: float = 0.0
var _shock_sparks: CPUParticles3D = null
var _splatter: Array[GPUParticles3D] = [] # per wheel: oil / glue drops flung off a coated tire
var _splash: Array[GPUParticles3D] = [] # per wheel: droplets where those drops land
var _splash_linger: Array[float] = []
var _trails: Array[TireTrail] = [] # per wheel: track on the ground
var _oil_ramp: GradientTexture1D = null
var _glue_ramp: GradientTexture1D = null
var _max_speed: float = 1.0
var _coating_time: float = 1.0
var _engine: AudioStreamPlayer3D = null
var _engine_air: AudioStreamPlayer3D = null
var _boost_sound: AudioStreamPlayer3D = null
var _drift_sound: AudioStreamPlayer3D = null
var _air_mix: float = 0.0 # 0 = ground engine, 1 = airborne engine
var _engine_db: float = ENGINE_DB_OTHER
var _time: float = 0.0

## Returns the model path to use. bot_index < 0 means the local player.
static func resolve_model_path(preferred: String, bot_index: int) -> String:
	if preferred != "" and ResourceLoader.exists(preferred):
		return preferred
	var names: Array[String] = []
	if bot_index >= 0:
		names.append(BOT_MODELS[bot_index % BOT_MODELS.size()])
	names.append_array(PLAYER_MODELS)
	for n in names:
		var path := MODEL_DIR + n + ".glb"
		if ResourceLoader.exists(path):
			return path
	for file in DirAccess.get_files_at(MODEL_DIR):
		var f := file.trim_suffix(".import").trim_suffix(".remap")
		if f.get_extension() == "glb":
			return MODEL_DIR + f
	return ""

func setup(model_scene: PackedScene, tuning: CarTuning, color: Color, is_local: bool) -> void:
	car = get_parent() as Car
	_base_color = color
	_is_local = is_local
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var sag := (tuning.mass * g * tuning.gravity_scale / Car.WHEELS) / tuning.spring_strength
	_rest_spring = tuning.suspension_rest_length - sag
	var ground_y := tuning.wheel_mounts[0].y - _rest_spring - tuning.wheel_radius
	if model_scene != null:
		item_mount.y = _setup_model(model_scene, ground_y)
	_build_item_mount()
	_build_label()
	_build_shadow()
	_build_particles(tuning, ground_y)
	_build_splatter(tuning, ground_y)
	_build_sounds()
	_build_shock_sparks()

func _process(delta: float) -> void:
	if car == null:
		return
	_time += delta
	var steer_blend := 1.0 - exp(-STEER_SHARPNESS * delta)
	for i in _pivots.size():
		var pivot := _pivots[i]
		var travel := clampf((_rest_spring - car.wheel_spring_len[i]) * SUSPENSION_VISUAL_SCALE,
			-SUSPENSION_VISUAL_DOWN, SUSPENSION_VISUAL_UP)
		_wheel_offset[i] = lerpf(_wheel_offset[i], travel, 1.0 - exp(-SUSPENSION_VISUAL_SHARPNESS * delta))
		pivot.position.y = _pivot_base[i].y + _wheel_offset[i]
		_wheel_angle[i] = fposmod(_wheel_angle[i] - car.forward_speed / _visual_wheel_radius * delta * _wheel_spin_sign, TAU)
		_wheels[i].basis = _wheel_basis[i] * Basis(Vector3.RIGHT, _wheel_angle[i])
		if i < 2:
			pivot.rotation.y = lerp_angle(pivot.rotation.y, car.last_steer * STEER_VISUAL_ANGLE, steer_blend)
	if _item_pivot != null:
		var target := 0.0   # Shocker / Blast sit facing forward
		var d := to_local(car.last_aim_point) - item_mount
		if _item != null and _item.aim_type != ItemDef.AimType.NONE and Vector2(d.x, d.z).length_squared() > 0.0001:
			target = atan2(-d.x, -d.z)
		_item_pivot.rotation.y = wrapf(lerp_angle(_item_pivot.rotation.y, target, 1.0 - exp(-ITEM_AIM_SHARPNESS * delta)), -PI, PI)
	for s in _smoke:
		if s.emitting != car.is_drifting:
			s.emitting = car.is_drifting
	if _flame != null and _flame.emitting != car.is_boosting:
		_flame.emitting = car.is_boosting
	_update_exhaust(delta)
	_update_splatter(delta)
	if _shock_sparks != null and _shock_sparks.emitting != (car.shock_left > 0.0):
		_shock_sparks.emitting = car.shock_left > 0.0
	if _label != null:
		_label.visible = Settings.show_name_labels
	_update_sounds(delta)
	_apply_body_roll()
	_update_shadow()

# --- Model and wheels --------------------------------------------------------------------------

## Instances, scales and places the model; returns the car-local y of its top (item mount height).
func _setup_model(model_scene: PackedScene, ground_y: float) -> float:
	_model = model_scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	if meshes.is_empty():
		push_warning("CarVisual: model has no meshes")
		return DEFAULT_ROOF_Y
	var aabb := _in_model(meshes[0]) * meshes[0].get_aabb()
	var xray := ShaderMaterial.new()   # silhouette in the player color where the car is hidden (§10.1)
	xray.shader = XRAY_SHADER
	xray.set_shader_parameter("color", Color(_base_color, XRAY_ALPHA))
	for mi in meshes:
		aabb = aabb.merge(_in_model(mi) * mi.get_aabb())
		mi.layers = Layers.RENDER_CARS
		mi.material_overlay = xray

	var rot := Basis(Vector3.UP, deg_to_rad(model_yaw_deg))
	var rotated := Transform3D(rot, Vector3.ZERO) * aabb
	var s := visual_length / rotated.size.z
	var center := rotated.get_center() * s
	_model.transform = Transform3D(rot.scaled(Vector3.ONE * s), Vector3(-center.x, ground_y - rotated.position.y * s, -center.z))
	_model_base = _model.transform
	_setup_wheels()
	return ground_y + rotated.size.y * s

func _setup_wheels() -> void:
	var found: Array[Node3D] = []
	_collect_wheels(_model, found)
	var names: Array[String] = []
	for w in found:
		names.append(String(w.name))
	var slots: Array[Node3D] = [null, null, null, null]
	var slot_xf: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D(), Transform3D()]
	if found.size() == Car.WHEELS:
		for w in found:
			var xf := _model.transform * _in_model(w)
			var idx := (0 if xf.origin.z < 0.0 else 2) + (0 if xf.origin.x < 0.0 else 1)
			slots[idx] = w
			slot_xf[idx] = xf
	if slots.has(null):
		push_warning("CarVisual: expected 4 wheels (FL, FR, RL, RR), found %s; wheel animation off" % [names])
		return

	for i in Car.WHEELS:
		var w := slots[i]
		var xf := slot_xf[i]
		var pivot := Node3D.new()
		pivot.name = "WheelPivot%d" % i
		pivot.position = xf.origin
		add_child(pivot)
		w.get_parent().remove_child(w)
		pivot.add_child(w)
		w.transform = Transform3D(xf.basis, Vector3.ZERO)
		_wheels.append(w)
		_wheel_basis.append(xf.basis)
		_wheel_angle.append(0.0)
		_pivots.append(pivot)
		_pivot_base.append(xf.origin)
	# Wheel local X may point along −car X after the model yaw; spin around it with the matching sign.
	_wheel_spin_sign = signf(slot_xf[0].basis.x.dot(Vector3.RIGHT))
	var mi := _wheels[0] as MeshInstance3D
	if mi != null:
		_visual_wheel_radius = (slot_xf[0].basis * mi.get_aabb().size).abs().y * 0.5

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_meshes(c, out)

func _collect_wheels(node: Node, out: Array[Node3D]) -> void:
	for c in node.get_children():
		if c is Node3D and String(c.name).containsn("wheel"):
			out.append(c as Node3D)
		else:
			_collect_wheels(c, out)

## Transform of a model descendant relative to the model root.
func _in_model(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != _model:
		xf = cur.transform * xf
		cur = cur.get_parent() as Node3D
	return xf

# --- Held item model on the roof (ItemModels), label, shadow -------------------------------------

## The held item's model sits on the roof; aimed items yaw toward car.last_aim_point.

func _build_item_mount() -> void:
	_item_pivot = Node3D.new()
	_item_pivot.name = "ItemMount"
	_item_pivot.position = item_mount
	add_child(_item_pivot)
	car.item_changed.connect(_on_item_changed)
	_on_item_changed(car.held_item)

func _on_item_changed(item: ItemDef) -> void:
	if item == _item:
		return
	_item = item
	if _item_model != null:
		_item_model.queue_free()
		_item_model = null
	muzzle = null
	if item == null:
		return
	_item_model = ItemModels.build(item)
	_item_model.name = "ItemModel"
	_item_pivot.add_child(_item_model)
	muzzle = _item_model.find_child("Muzzle", true, false) as Node3D
	_item_model.scale = Vector3.ONE * 0.01
	_item_model.create_tween().tween_property(_item_model, "scale", Vector3.ONE, ITEM_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _build_label() -> void:
	var label := Label3D.new()
	_label = label
	label.name = "NameLabel"
	label.text = car.display_name if car != null else ""
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.pixel_size = LABEL_PIXEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.outline_size = LABEL_OUTLINE_SIZE
	label.modulate = _base_color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position.y = LABEL_HEIGHT
	label.layers = Layers.RENDER_CARS
	add_child(label)

func _build_shadow() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, SHADOW_ALPHA))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = SHADOW_TEXTURE_SIZE
	tex.height = SHADOW_TEXTURE_SIZE
	_shadow = Decal.new()
	_shadow.name = "BlobShadow"
	_shadow.size = SHADOW_SIZE
	_shadow.texture_albedo = tex
	_shadow.cull_mask = Layers.RENDER_WORLD
	# Stays upright in world space while the car tilts or flips; moved in _process from the interpolated car.
	_shadow.top_level = true
	_shadow.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_shadow)
	_update_shadow()

# --- Particles: drift smoke at the rear wheels, boost flame at the rear --------------------------

func _build_particles(tuning: CarTuning, ground_y: float) -> void:
	for i: int in [2, 3]: # rear-left, rear-right
		var m: Vector3 = tuning.wheel_mounts[i]
		var smoke_ramp := Gradient.new()
		smoke_ramp.set_color(0, SMOKE_COLOR)
		smoke_ramp.set_color(1, Color(SMOKE_COLOR, 0.0))
		var smoke := _particles("DriftSmoke%d" % i, Vector3(m.x, ground_y + SMOKE_LIFT, m.z), SMOKE_SIZE, smoke_ramp, false)
		var pm := smoke.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 40.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.2
		pm.gravity = Vector3(0.0, 0.6, 0.0) # drifts upward
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		smoke.amount = 32
		smoke.lifetime = 0.9
		_smoke.append(smoke)

	var flame_ramp := Gradient.new()
	flame_ramp.set_color(0, FLAME_COLOR)
	flame_ramp.set_color(1, FLAME_FADE_COLOR)
	_flame = _particles("BoostFlame", FLAME_OFFSET, FLAME_SIZE, flame_ramp, true)
	var fm := _flame.process_material as ParticleProcessMaterial
	fm.direction = Vector3.BACK # out of the rear (+Z car-local)
	fm.spread = 10.0
	fm.initial_velocity_min = 3.0
	fm.initial_velocity_max = 6.0
	fm.gravity = Vector3.ZERO
	fm.scale_min = 0.5
	fm.scale_max = 1.0
	_flame.amount = 40
	_flame.lifetime = 0.25
	_build_exhaust()

## Blue exhaust cone behind the car while boosting: an outer glow plus a brighter core, flickering.
func _build_exhaust() -> void:
	_exhaust = Node3D.new()
	_exhaust.name = "BoostExhaust"
	_exhaust.position = FLAME_OFFSET
	_exhaust.visible = false
	add_child(_exhaust)
	_add_cone(EXHAUST_OUTER, EXHAUST_OUTER_COLOR)
	_add_cone(EXHAUST_CORE, EXHAUST_CORE_COLOR)

func _add_cone(size: Vector2, color: Color) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0 # tip, ends up pointing out of the rear
	cone.bottom_radius = size.x
	cone.height = size.y
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 16
	cone.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = EXHAUST_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("half_length", size.y * 0.5)
	_exhaust_mats.append(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.rotation.x = PI * 0.5 # mesh +Y (tip) → car +Z (backwards)
	mi.position.z = size.y * 0.5 # base at the nozzle
	mi.layers = Layers.RENDER_CARS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_exhaust.add_child(mi)

func _update_exhaust(delta: float) -> void:
	if _exhaust == null:
		return
	_exhaust_amount = move_toward(_exhaust_amount, 1.0 if car.is_boosting else 0.0, delta * EXHAUST_FADE_SPEED)
	_exhaust.visible = _exhaust_amount > 0.01
	if not _exhaust.visible:
		return
	var flicker := EXHAUST_FLICKER * (sin(_time * EXHAUST_FLICKER_SPEED) * 0.6 + sin(_time * EXHAUST_FLICKER_SPEED * 2.3) * 0.4)
	var width := lerpf(0.4, 1.0, _exhaust_amount) * (1.0 - flicker * 0.5)
	_exhaust.scale = Vector3(width, width, _exhaust_amount * (1.0 + flicker))
	for mat in _exhaust_mats:
		mat.set_shader_parameter("intensity", _exhaust_amount * (0.85 + flicker))

## Billboard particles with a soft round sprite and a color ramp. Off until _process switches them on.
func _particles(node_name: String, pos: Vector3, sprite_size: float, ramp: Gradient, additive: bool) -> GPUParticles3D:
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	var pm := ParticleProcessMaterial.new()
	pm.color_ramp = ramp_tex
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * sprite_size
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = node_name
	p.process_material = pm
	p.draw_pass_1 = quad
	p.local_coords = false
	p.emitting = false
	p.position = pos
	p.layers = Layers.RENDER_CARS
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	return tex

# --- Sounds: engine (same for every car), airborne engine, boost, drift --------------------------

func _build_sounds() -> void:
	if not Game.audio.enabled:
		return
	_engine_db = ENGINE_DB_LOCAL if _is_local else ENGINE_DB_OTHER
	_engine = _sound_player("EngineSound", Game.audio.bank.looping(&"engine"), AudioDirector.BUS_ENGINE)
	_engine_air = _sound_player("AirEngineSound", Game.audio.bank.looping(&"engine_air"), AudioDirector.BUS_ENGINE)
	_boost_sound = _sound_player("BoostSound", Game.audio.bank.looping(&"boost"), AudioDirector.BUS_SFX)
	_drift_sound = _sound_player("DriftSound", null, AudioDirector.BUS_SFX)
	_engine.volume_db = _engine_db
	_engine_air.volume_db = SILENT_DB
	_boost_sound.volume_db = BOOST_DB
	_drift_sound.volume_db = DRIFT_DB
	if _engine.stream != null:
		_engine.play()
	if _engine_air.stream != null:
		_engine_air.play()

func _sound_player(node_name: String, stream: AudioStream, bus: StringName) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.stream = stream
	p.bus = bus
	p.unit_size = SOUND_UNIT_SIZE
	add_child(p)
	return p

func _update_sounds(delta: float) -> void:
	if _engine == null:
		return
	if car.eliminated or mute_engine:
		for p: AudioStreamPlayer3D in [_engine, _engine_air, _boost_sound, _drift_sound]:
			if p.playing:
				p.stop()
		return
	if not _engine.playing and _engine.stream != null:
		_engine.play()
		_engine_air.play()
	var top := car.tuning.max_speed * car.tuning.boost_speed_mult
	var revs := clampf(absf(car.forward_speed) / top, 0.0, 1.0)
	var pitch := lerpf(ENGINE_PITCH_IDLE, ENGINE_PITCH_TOP, revs)
	# Airborne: cross-fade to the free-revving motor.
	_air_mix = move_toward(_air_mix, 1.0 if car.grounded_count == 0 else 0.0, delta * ENGINE_FADE)
	_engine.pitch_scale = pitch
	_engine_air.pitch_scale = pitch + AIR_PITCH_EXTRA
	_engine.volume_db = _engine_db + linear_to_db(maxf(1.0 - _air_mix, 0.001))
	_engine_air.volume_db = _engine_db + linear_to_db(maxf(_air_mix, 0.001))

	if car.is_boosting and not _boost_sound.playing and _boost_sound.stream != null:
		_boost_sound.play()
	elif not car.is_boosting and _boost_sound.playing:
		_boost_sound.stop()
	# Tire squeaks don't loop cleanly; play the next variation whenever the last one ends.
	if car.is_drifting and not _drift_sound.playing:
		_drift_sound.stream = Game.audio.bank.next(&"drift")
		if _drift_sound.stream != null:
			_drift_sound.play()
	elif not car.is_drifting and _drift_sound.playing:
		_drift_sound.stop()

# --- Oil / glue: drops flung off coated wheels, droplets where they land, tracks on the ground -------

func _build_splatter(tuning: CarTuning, ground_y: float) -> void:
	_max_speed = tuning.max_speed
	_coating_time = tuning.wheel_coating_time
	_oil_ramp = _color_variations(ItemRegistry.OIL_COLOR, 0.6, 0.1)
	_glue_ramp = _color_variations(ItemRegistry.GLUE_COLOR, 0.3, 0.3)
	var drop := _drop_mesh(SPLATTER_DROP_RADIUS, SPLATTER_DROP_RADIUS * 2.0 * SPLATTER_DROP_STRETCH)
	var droplet := _drop_mesh(SPLASH_DROPLET_RADIUS, SPLASH_DROPLET_RADIUS)   # flattened: lies on the surface
	var drop_shrink := _curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.3)])
	var droplet_shrink := _curve_texture([Vector2(0.0, 1.0), Vector2(0.6, 1.0), Vector2(1.0, 0.0)])
	for i in Car.WHEELS:
		# Droplets: spawned by the drops below when they hit the arena (particle heightfield, slopes included).
		var spm := ParticleProcessMaterial.new()
		spm.direction = Vector3.UP
		spm.spread = SPLASH_SPREAD
		spm.initial_velocity_min = SPLASH_SPEED_MIN
		spm.initial_velocity_max = SPLASH_SPEED_MAX
		spm.gravity = Vector3(0.0, -SPLATTER_GRAVITY, 0.0)
		spm.scale_min = 0.5
		spm.scale_max = 1.5
		spm.scale_curve = droplet_shrink
		spm.color_initial_ramp = _oil_ramp
		spm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		spm.collision_bounce = SPLASH_BOUNCE
		spm.collision_friction = 1.0
		spm.collision_use_scale = true
		var splash := GPUParticles3D.new()
		splash.name = "WheelSplash%d" % i
		splash.top_level = true # world-space directions (UP is up)
		splash.process_material = spm
		splash.draw_pass_1 = droplet
		splash.amount = SPLASH_AMOUNT
		splash.lifetime = SPLASH_LIFETIME
		splash.local_coords = false
		splash.emitting = false
		splash.collision_base_size = SPLASH_DROPLET_RADIUS
		splash.layers = Layers.RENDER_CARS
		splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		splash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(splash)
		_splash.append(splash)
		_splash_linger.append(0.0)

		# Drops: stretched along their flight, random size / color / direction; burst into droplets on contact.
		var m: Vector3 = tuning.wheel_mounts[i]
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.1, tuning.wheel_radius * 0.6, tuning.wheel_radius * 0.6)
		pm.spread = SPLATTER_SPREAD
		pm.gravity = Vector3(0.0, -SPLATTER_GRAVITY, 0.0)
		pm.scale_min = 0.4
		pm.scale_max = 1.3
		pm.scale_curve = drop_shrink
		pm.color_initial_ramp = _oil_ramp
		pm.set_particle_flag(ParticleProcessMaterial.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
		pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
		pm.collision_use_scale = true
		pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
		pm.sub_emitter_amount_at_collision = SPLASH_DROPLETS
		var p := GPUParticles3D.new()
		p.name = "WheelSplatter%d" % i
		p.process_material = pm
		p.draw_pass_1 = drop
		p.amount = SPLATTER_AMOUNT
		p.lifetime = SPLATTER_LIFETIME
		p.randomness = 1.0
		p.local_coords = false
		p.emitting = false
		p.collision_base_size = SPLATTER_DROP_RADIUS
		p.sub_emitter = NodePath("../" + splash.name)
		p.position = Vector3(m.x, ground_y + tuning.wheel_radius, m.z)
		p.layers = Layers.RENDER_CARS
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_splatter.append(p)

		var trail := TireTrail.new()
		trail.name = "TireTrail%d" % i
		add_child(trail)
		_trails.append(trail)

## Coated wheels shed drops: a few drips when slow, a spray thrown back and up when fast.
func _update_splatter(delta: float) -> void:
	var t := clampf(absf(car.forward_speed) / _max_speed, 0.0, 1.0)
	for i in _splatter.size():
		var p := _splatter[i]
		var splash := _splash[i]
		var kind := _coat_kind(i)
		var coated := kind >= 0
		if p.emitting != coated:
			p.emitting = coated
		# Droplets keep coming while drops of a just-cleaned tire are still in the air.
		_splash_linger[i] = SPLATTER_LIFETIME if coated else maxf(0.0, _splash_linger[i] - delta)
		if splash.emitting != (_splash_linger[i] > 0.0):
			splash.emitting = _splash_linger[i] > 0.0
		if not coated:
			continue
		var pm := p.process_material as ParticleProcessMaterial
		var ramp := _oil_ramp if kind == ItemDef.Kind.OIL else _glue_ramp
		if pm.color_initial_ramp != ramp:
			pm.color_initial_ramp = ramp
			(splash.process_material as ParticleProcessMaterial).color_initial_ramp = ramp
		pm.direction = Vector3(0.0, SPLATTER_RISE, 1.0 if car.forward_speed >= 0.0 else -1.0).normalized()
		var v := lerpf(SPLATTER_DRIP_SPEED, SPLATTER_FLING_SPEED, t)
		pm.initial_velocity_min = v * 0.3
		pm.initial_velocity_max = v
		p.amount_ratio = lerpf(SPLATTER_DRIP_RATIO, 1.0, t)

## Tracks follow the wheels' ground contacts every physics tick.
func _physics_process(_delta: float) -> void:
	if car == null or _trails.is_empty():
		return
	var heading := -car.global_basis.z
	for i in _trails.size():
		var kind := _coat_kind(i)
		var strength := 0.0
		if kind >= 0 and car.wheel_grounded[i]:
			strength = maxf(car.wheel_oil[i], car.wheel_glue[i]) / _coating_time
		_trails[i].track(kind, car.wheel_contact[i], car.wheel_normal[i], heading, strength)

## What a wheel is coated with (ItemDef.Kind.OIL / GLUE, the fresher coat wins), or -1 when clean.
func _coat_kind(i: int) -> int:
	var oil := car.wheel_oil[i]
	var glue := car.wheel_glue[i]
	if oil <= 0.0 and glue <= 0.0:
		return -1
	return ItemDef.Kind.OIL if oil >= glue else ItemDef.Kind.GLUE

## Random per-particle shades of a color (darker … lighter).
func _color_variations(c: Color, darker: float, lighter: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, c.darkened(darker))
	g.set_color(1, c.lightened(lighter))
	g.add_point(0.5, c)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

func _drop_mesh(radius: float, height: float) -> SphereMesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.3 # wet sheen, without mirroring the bright sky
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = mat
	return mesh

func _curve_texture(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for pt in points:
		curve.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

## Blue electric sparks crackling around a car slowed by the Shocker.
func _build_shock_sparks() -> void:
	_shock_sparks = CPUParticles3D.new()
	_shock_sparks.name = "ShockSparks"
	_shock_sparks.amount = 24
	_shock_sparks.lifetime = 0.3
	_shock_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_shock_sparks.emission_box_extents = Vector3(0.6, 0.3, 1.0)
	_shock_sparks.direction = Vector3.UP
	_shock_sparks.spread = 180.0
	_shock_sparks.initial_velocity_min = 1.0
	_shock_sparks.initial_velocity_max = 3.0
	_shock_sparks.gravity = Vector3.ZERO
	_shock_sparks.color = Color(0.5, 0.9, 1.0)
	_shock_sparks.mesh = Effects.particle_mesh(0.07)
	_shock_sparks.emitting = false
	_shock_sparks.position.y = 0.2
	add_child(_shock_sparks)

## Rolls the chassis (model and held item) around the car's length axis, leaving the wheel pivots alone.
func _apply_body_roll() -> void:
	var roll := Transform3D(Basis(Vector3.BACK, body_roll), Vector3.ZERO)
	if _model != null:
		_model.transform = roll * _model_base
	if _item_pivot != null:
		_item_pivot.position = roll * item_mount

func _update_shadow() -> void:
	if _shadow == null or car == null:
		return
	var xf := car.get_global_transform_interpolated()
	var fwd := -xf.basis.z
	var yaw := atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length_squared() > 0.001 else _shadow.rotation.y
	_shadow.global_transform = Transform3D(Basis(Vector3.UP, yaw), xf.origin + Vector3.UP * (SHADOW_TOP - SHADOW_SIZE.y * 0.5))
