@tool
class_name MapFluid
extends Node3D
## A fluid area: water, lava, mud, acid … Put the node at the middle of the surface; the box reaches Size.y
## (depth) down. Turn it around the vertical only (fluids stay level); scaling multiplies the size.
## Choose a Preset and click "Apply preset values" to load its defaults, then tweak anything.
## No collision: cars drive or sink into it (put it in a dip of the terrain or between walls).

enum Preset { WATER, LAVA, MUD, ACID }   # same order as FluidPresets.NAMES

@export_tool_button("Apply preset values", "Reload") var apply_preset_action: Callable = apply_preset

@export var preset: Preset = Preset.WATER:
	set(v):
		preset = v
		_refresh()
@export var size: Vector3 = Vector3(8.0, 1.0, 8.0):   # x, depth, z
	set(v):
		size = v.clamp(Vector3.ONE * MapLoader.SIZE_RANGE.x, Vector3.ONE * MapLoader.SIZE_RANGE.y)
		_refresh()
@export var color: Color = Color("#3E8FD6"):
	set(v):
		color = v
		_refresh()
@export_range(0.05, 1.0, 0.01) var opacity: float = 0.72:
	set(v):
		opacity = v
		_refresh()
## Optional: a PNG from this map's textures/ folder (maps/<id>/textures/), tiled over the surface.
@export var texture: Texture2D = null:
	set(v):
		texture = v
		_refresh()

@export_group("Effect on cars")
@export_range(0.0, 100.0, 0.1, "suffix:per 100 ms") var damage: float = 0.0
@export_range(0.05, 1.0, 0.01) var slow: float = 0.7          # top speed × while touching (1 = no slowdown)
@export_range(0.0, 10.0, 0.1) var drag: float = 0.8           # how quickly a car in it loses speed
@export_range(0.0, 3.0, 0.05) var buoyancy: float = 0.55      # 0 = sinks to the bottom, 1 = floats when fully under
@export_range(0.05, 2.0, 0.05) var grip: float = 0.8          # tyre grip × while touching
@export var kill: bool = false                                 # touching it = falling off the map (lava pits)
@export var current: Vector2 = Vector2.ZERO:                  # m/s along the fluid's own X / Z (rivers)
	set(v):
		current = v.limit_length(MapLoader.MAX_CURRENT)
		_refresh()
@export_range(0.0, 10.0, 0.1, "suffix:s") var coat: float = 3.0   # wet tyre tracks after leaving

var _preview: Node3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh()

func preset_name() -> String:
	return FluidPresets.NAMES[preset]

## Loads the chosen preset's default values (look and effect).
func apply_preset() -> void:
	var p := FluidPresets.get_preset(preset_name())
	color = p["color"]
	opacity = p["opacity"]
	damage = p["damage"]
	slow = p["slow"]
	drag = p["drag"]
	buoyancy = p["buoyancy"]
	grip = p["grip"]
	coat = p["coat"]
	notify_property_list_changed()

func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	FluidZone.build_visual(_preview, preset_name(), size, color, opacity, texture, global_basis * Vector3(current.x, 0.0, current.y))
	# The volume below the surface, faintly.
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	var volume := MeshInstance3D.new()
	volume.mesh = box
	volume.position = Vector3.DOWN * size.y * 0.5
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.add_child(volume)
