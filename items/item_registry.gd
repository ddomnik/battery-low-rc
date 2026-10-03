class_name ItemRegistry
## Item definitions (§7.6.1). Order matters: the debug keys 1–4 give items by index.

const ROCKET_COLOR := Color(1.0, 0.55, 0.15)
const BALLOON_COLOR := Color(0.3, 0.6, 1.0)
const BATTERY_COLOR := Color(0.45, 0.95, 0.35)

static func all() -> Array[ItemDef]:
	var defs: Array[ItemDef] = [_battery_pack(), _bottle_rocket(), _water_balloon(), _rocket_trio()]
	return defs

static func _battery_pack() -> ItemDef:
	var d := _base(&"battery_pack", "Battery Pack", ItemDef.Kind.BATTERY, ItemDef.AimType.NONE, BATTERY_COLOR, 35.0, 5.0)
	d.battery_amount = 0.5
	return d

static func _bottle_rocket() -> ItemDef:
	return _rocket(&"bottle_rocket", "Bottle Rocket", 1, 0.0, 40.0, 25.0)

static func _rocket_trio() -> ItemDef:
	return _rocket(&"rocket_trio", "Rocket Trio", 3, 24.0, 0.0, 40.0)

static func _water_balloon() -> ItemDef:
	var d := _base(&"water_balloon", "Water Balloon", ItemDef.Kind.BALLOON, ItemDef.AimType.LOB, BALLOON_COLOR, 25.0, 30.0)
	d.max_range = 22.0
	d.gravity = 25.0
	d.lifetime = 3.0
	d.explosion_radius = 4.5
	d.knockback = 13.0
	d.up_knockback = 10.0       # ~2.5 m hop at the center (gravity ×2), linear falloff to the edge
	return d

static func _rocket(id: StringName, display_name: String, count: int, spread: float, w_leader: float, w_last: float) -> ItemDef:
	var d := _base(id, display_name, ItemDef.Kind.ROCKET, ItemDef.AimType.STRAIGHT, ROCKET_COLOR, w_leader, w_last)
	d.count = count
	d.spread_deg = spread
	d.speed = 35.0
	d.max_pitch_deg = 25.0
	d.gravity = 0.0
	d.lifetime = 3.0
	d.explosion_radius = 3.5
	d.knockback = 16.0
	d.up_knockback = 10.0       # ~2.5 m hop at the center (gravity ×2), linear falloff to the edge
	return d

static func _base(id: StringName, display_name: String, kind: ItemDef.Kind, aim: ItemDef.AimType, color: Color,
		w_leader: float, w_last: float) -> ItemDef:
	var d := ItemDef.new()
	d.id = id
	d.display_name = display_name
	d.kind = kind
	d.aim_type = aim
	d.color = color
	d.weight_leader = w_leader
	d.weight_last = w_last
	return d
