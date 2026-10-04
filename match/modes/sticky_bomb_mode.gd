class_name StickyBombMode
extends GameMode
## Sticky bomb: a random car drags a bomb on a chain (cosmetic swing / drag) with a countdown and passes it on
## by touching another car.
## At zero it explodes: the holder is out and a fresh bomb goes to a random survivor. Last car left wins.

const PASS_COOLDOWN := 1.0           # s after a hand-over before the bomb can move again (no instant pass-back)
const BLAST_RADIUS := 5.0
const BLAST_KNOCKBACK := 12.0
const BLAST_UP := 9.0
const LAUNCH_UP := 18.0              # the holder is thrown up this fast (m/s) …
const LAUNCH_SPIN := 7.0             # … spinning (rad/s around a random tilted axis)
const MIN_FLIGHT := 0.5              # s before a touchdown counts
const MAX_FLIGHT := 4.0              # bursts after this long even without touching anything
const BURST_RADIUS := 3.5            # camera shake size of the burst
const BOMB_RADIUS := 0.42
const CHAIN_ANCHOR := Vector3(0.0, 0.0, 1.0)   # car-local, the middle of the rear
const CHAIN_LENGTH := 1.4            # anchor to the bomb's surface
const CHAIN_LINKS := 9
const CHAIN_LINK_RADII := Vector2(0.035, 0.075)   # torus inner / outer
const CHAIN_LINK_STRETCH := 1.5      # links are oval along the chain
const CHAIN_SAG := 0.6               # how much slack hangs down (share of the missing length)
const CHAIN_COLOR := Color(0.42, 0.43, 0.46)
const BOMB_GRAVITY := 20.0           # the bomb swings and drops (cosmetic, matches the cars' gravity × 2)
const BOMB_AIR_DAMPING := 1.2        # 1/s
const BOMB_GROUND_FRICTION := 5.0    # 1/s, sliding along the ground
const FLOOR_PROBE := 3.0
const FUSE_BLINK_FAST_BELOW := 3.0   # s left when the light starts blinking fast
const LABEL_FONT_SIZE := 64
const LABEL_HEIGHT_ON_BOMB := 0.55    # countdown digits are this tall (m), centered on the bomb …
const LABEL_PRIORITY := 100           # … and drawn over everything
const FUSE_LENGTH := 0.32
const FUSE_TILT_DEG := 25.0
const FUSE_COLOR := Color(0.55, 0.42, 0.28)
const SPARK_COLOR := Color(1.0, 0.55, 0.1)
const SPARK_FAST_SPEED_SCALE := 1.8   # sparks spit faster when the fuse is nearly done
const GOT_IT_COLOR := Color(1.0, 0.35, 0.25)
const PASSED_COLOR := Color(0.5, 1.0, 0.5)

var holder: Car = null
var time_left: float = 0.0

var _cooldown: float = 0.0
var _doomed: Car = null              # thrown into the air by the bomb; bursts when it comes down
var _doomed_time: float = 0.0
var _bomb: Node3D = null             # top-level (world space), child of the holder's visual
var _bomb_prev: Vector3 = Vector3.ZERO   # last frame's position (Verlet)
var _links: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D = null
var _label: Label3D = null
var _sparks: CPUParticles3D = null
var _blink: float = 0.0

func _ready() -> void:
	for car in match_node.cars:
		car.touched.connect(_on_touched)
	_build_bomb()

func on_round_start() -> void:
	_give_to_random()

func on_round_end() -> void:
	if _bomb != null:
		_bomb.queue_free()
		_bomb = null

func score_text(car: Car) -> String:
	if match_node.eliminated_order.has(car):
		return "OUT"
	return "BOMB" if car == holder else "IN"

func status_text() -> String:
	if holder == null:
		return ""
	return "BOMB: %s  %d" % [holder.display_name, ceili(time_left)]

func on_fell_off(car: Car) -> bool:
	if car == _doomed:
		_burst()
		return false
	return true

func _physics_process(delta: float) -> void:
	if not Net.is_authority() or match_node.state != Match.State.PLAYING:
		return
	if _doomed != null:
		_doomed_time += delta
		var down := _doomed.grounded_count > 0 or _doomed.get_contact_count() > 0
		if (_doomed_time > MIN_FLIGHT and down) or _doomed_time > MAX_FLIGHT:
			_burst()
	if holder == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	time_left -= delta
	if time_left <= 0.0:
		_explode()

func _process(delta: float) -> void:
	if _bomb == null or holder == null:
		return
	_label.text = str(ceili(maxf(time_left, 0.0)))
	_swing(delta)
	_blink += delta * (10.0 if time_left < FUSE_BLINK_FAST_BELOW else 3.0)
	_light_mat.emission_energy_multiplier = 3.0 if fmod(_blink, 1.0) < 0.5 else 0.2
	_sparks.speed_scale = SPARK_FAST_SPEED_SCALE if time_left < FUSE_BLINK_FAST_BELOW else 1.0

## Touching passes the bomb (either car may report the contact).
func _on_touched(car: Car, other: Car) -> void:
	if not Net.is_authority() or match_node.state != Match.State.PLAYING or _cooldown > 0.0:
		return
	if car == holder and not other.eliminated:
		_hand_over(other)
	elif other == holder and not car.eliminated:
		_hand_over(car)

func _hand_over(to: Car) -> void:
	var from := holder
	_attach(to)
	_cooldown = PASS_COOLDOWN
	if to == match_node.local_car:
		match_node.popup("YOU HAVE THE BOMB!", GOT_IT_COLOR)
	elif from == match_node.local_car:
		match_node.popup("PASSED!", PASSED_COLOR)
	match_node.scores_changed.emit()

## The bomb goes off: nearby cars are blasted away and the holder is thrown into the air, spinning. It breaks
## apart when it comes down (_burst); only then does the next bomb appear.
func _explode() -> void:
	var victim := holder
	holder = null
	_bomb.visible = false
	match_node.explode(victim.global_position, BLAST_RADIUS, BLAST_KNOCKBACK, BLAST_UP, null, 3.0, 1.5, &"explosion", victim)
	victim.frozen = true   # no control while flying
	var axis := Vector3(match_node.rng.randf_range(-1.0, 1.0), 0.5, match_node.rng.randf_range(-1.0, 1.0)).normalized()
	victim.apply_knockback(Vector3.UP * LAUNCH_UP, 0.0, axis * LAUNCH_SPIN)
	_doomed = victim
	_doomed_time = 0.0
	match_node.scores_changed.emit()

func _burst() -> void:
	var car := _doomed
	_doomed = null
	match_node.play_effect(&"car_burst", car.global_position, BURST_RADIUS, car.color)
	match_node.eliminate(car)
	if match_node.alive_cars().size() >= 2:
		_give_to_random()
	match_node.scores_changed.emit()

func _give_to_random() -> void:
	var alive := match_node.alive_cars()
	alive.erase(_doomed)
	if alive.is_empty():
		return
	time_left = match_node.config.bomb_time
	_attach(alive[match_node.rng.randi() % alive.size()])
	if holder == match_node.local_car:
		match_node.popup("YOU HAVE THE BOMB!", GOT_IT_COLOR)

func _attach(car: Car) -> void:
	holder = car
	_bomb.reparent(car.visual, false)
	_bomb.top_level = true
	var xf := car.get_global_transform_interpolated()
	var start := xf * (CHAIN_ANCHOR + Vector3.BACK * (CHAIN_LENGTH + BOMB_RADIUS))
	_bomb.global_transform = Transform3D(Basis.IDENTITY, start)
	_bomb_prev = start
	_bomb.visible = true

## The bomb hangs on its chain behind the holder: it swings, drops, slides along the ground and gets pulled
## along when the chain is tight (Verlet, per frame; purely cosmetic).
func _swing(delta: float) -> void:
	if delta <= 0.0:
		return
	var anchor := holder.get_global_transform_interpolated() * CHAIN_ANCHOR
	var cur := _bomb.global_position
	var vel := (cur - _bomb_prev) * (1.0 - minf(BOMB_AIR_DAMPING * delta, 1.0))
	var next := cur + vel + Vector3.DOWN * BOMB_GRAVITY * delta * delta
	var reach := CHAIN_LENGTH + BOMB_RADIUS
	var off := next - anchor
	if off.length() > reach:
		next = anchor + off.normalized() * reach
	var floor_y := _floor_below(next)
	var on_ground := next.y < floor_y + BOMB_RADIUS
	if on_ground:
		next.y = floor_y + BOMB_RADIUS
	_bomb_prev = cur
	if on_ground:   # friction: take some of the sliding speed out of the history
		var slide := next - cur
		_bomb_prev = next - Vector3(slide.x, maxf(slide.y, 0.0), slide.z) * (1.0 - minf(BOMB_GROUND_FRICTION * delta, 1.0))
	_bomb.global_position = next
	_update_chain(anchor, next)

func _floor_below(at: Vector3) -> float:
	var space := holder.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * FLOOR_PROBE, Layers.WORLD))
	return (hit.position as Vector3).y if not hit.is_empty() else -INF

## Links from the car's rear to the bomb, sagging when there is slack, every other one turned 90°.
func _update_chain(anchor: Vector3, bomb_pos: Vector3) -> void:
	var attach := bomb_pos + (anchor - bomb_pos).normalized() * BOMB_RADIUS
	var span := attach - anchor
	var sag := maxf(CHAIN_LENGTH - span.length(), 0.0) * CHAIN_SAG
	for k in _links.size():
		var t := (k + 0.5) / _links.size()
		var p := anchor + span * t + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var dir := span + Vector3.DOWN * sag * 4.0 * (1.0 - 2.0 * t)
		if dir.length_squared() < 0.0001:
			continue
		var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD
		var b := Basis.looking_at(dir, up) * Basis(Vector3.FORWARD, PI * 0.5 * (k % 2))
		_links[k].global_transform = Transform3D(b.scaled_local(Vector3(1.0, 1.0, CHAIN_LINK_STRETCH)), p)

func _build_bomb() -> void:
	_bomb = Node3D.new()
	_bomb.name = "StickyBomb"
	_bomb.visible = false
	_bomb.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved per frame by _swing
	add_child(_bomb)
	var link_mat := StandardMaterial3D.new()
	link_mat.albedo_color = CHAIN_COLOR
	link_mat.metallic = 0.8
	link_mat.roughness = 0.35
	var link_mesh := TorusMesh.new()
	link_mesh.inner_radius = CHAIN_LINK_RADII.x
	link_mesh.outer_radius = CHAIN_LINK_RADII.y
	link_mesh.rings = 12
	link_mesh.ring_segments = 6
	link_mesh.material = link_mat
	for k in CHAIN_LINKS:
		var link := MeshInstance3D.new()
		link.mesh = link_mesh
		link.layers = Layers.RENDER_CARS
		_bomb.add_child(link)
		_links.append(link)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.08, 0.1)
	body_mat.roughness = 0.35
	var sphere := SphereMesh.new()
	sphere.radius = BOMB_RADIUS
	sphere.height = BOMB_RADIUS * 2.0
	var body := MeshInstance3D.new()
	body.mesh = sphere
	body.material_override = body_mat
	body.layers = Layers.RENDER_CARS
	_bomb.add_child(body)
	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(1.0, 0.15, 0.1)
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1.0, 0.15, 0.1)
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.09
	light_mesh.height = 0.18
	# Fuse: a short cord out of the top, the blinking ember at its tip spitting orange sparks.
	var fuse_dir := Vector3(0.0, cos(deg_to_rad(FUSE_TILT_DEG)), sin(deg_to_rad(FUSE_TILT_DEG)))
	var fuse_base := Vector3(0.0, BOMB_RADIUS * 0.92, 0.0)
	var fuse_tip := fuse_base + fuse_dir * FUSE_LENGTH
	var fuse_mat := StandardMaterial3D.new()
	fuse_mat.albedo_color = FUSE_COLOR
	var fuse_mesh := CylinderMesh.new()
	fuse_mesh.top_radius = 0.025
	fuse_mesh.bottom_radius = 0.03
	fuse_mesh.height = FUSE_LENGTH
	var fuse := MeshInstance3D.new()
	fuse.mesh = fuse_mesh
	fuse.material_override = fuse_mat
	fuse.position = (fuse_base + fuse_tip) * 0.5
	fuse.rotation.x = deg_to_rad(FUSE_TILT_DEG)
	fuse.layers = Layers.RENDER_CARS
	_bomb.add_child(fuse)
	var light := MeshInstance3D.new()
	light.mesh = light_mesh
	light.material_override = _light_mat
	light.position = fuse_tip
	light.layers = Layers.RENDER_CARS
	_bomb.add_child(light)
	_sparks = CPUParticles3D.new()
	_sparks.name = "FuseSparks"
	_sparks.amount = 40
	_sparks.lifetime = 0.45
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 2.8
	_sparks.gravity = Vector3(0.0, -6.0, 0.0)
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.2
	_sparks.mesh = Effects.particle_mesh(0.05)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4))
	ramp.add_point(0.3, SPARK_COLOR)
	ramp.set_color(ramp.get_point_count() - 1, Color(SPARK_COLOR.darkened(0.4), 0.0))
	_sparks.color_ramp = ramp
	_sparks.local_coords = false
	_sparks.position = fuse_tip
	_sparks.layers = Layers.RENDER_CARS
	_bomb.add_child(_sparks)
	# Countdown on the bomb itself: smaller than the bomb, drawn on top of everything.
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = LABEL_PRIORITY
	_label.outline_render_priority = LABEL_PRIORITY - 1
	_label.font_size = LABEL_FONT_SIZE
	_label.pixel_size = LABEL_HEIGHT_ON_BOMB / LABEL_FONT_SIZE
	_label.outline_size = 12
	_label.modulate = Color(1.0, 0.3, 0.2)
	_label.layers = Layers.RENDER_CARS
	_bomb.add_child(_label)
