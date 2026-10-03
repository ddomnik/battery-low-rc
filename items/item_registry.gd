class_name ItemRegistry
## Item definitions (§7.6.1, extended). Order matters: the debug keys 1–7 give items by index.

const ROCKET_COLOR := Color(1.0, 0.55, 0.15)
const BALLOON_COLOR := Color(0.3, 0.6, 1.0)
const OIL_COLOR := Color(0.25, 0.22, 0.2)
const GLUE_COLOR := Color(0.85, 0.95, 0.3)
const SHOCK_COLOR := Color(0.45, 0.85, 1.0)
const BLAST_COLOR := Color(1.0, 0.35, 0.3)

static func all() -> Array[ItemDef]:
	var defs: Array[ItemDef] = [_bottle_rocket(), _water_balloon(), _rocket_trio(), _oil_slick(), _sticky_glue(),
		_shocker(), _blast()]
	return defs

static func _bottle_rocket() -> ItemDef:
	return _rocket(&"bottle_rocket", "Bottle Rocket", 1, 0.0, 35.0, 20.0)

static func _rocket_trio() -> ItemDef:
	return _rocket(&"rocket_trio", "Rocket Trio", 3, 24.0, 0.0, 25.0)

static func _water_balloon() -> ItemDef:
	var d := _base(&"water_balloon", "Water Balloon", ItemDef.Kind.BALLOON, ItemDef.AimType.LOB, BALLOON_COLOR, 25.0, 20.0)
	d.max_range = 22.0
	d.gravity = 25.0
	d.lifetime = 3.0
	d.explosion_radius = 4.5
	d.knockback = 13.0
	d.up_knockback = 10.0       # ~2.5 m hop at the center (gravity ×2), linear falloff to the edge
	return d

## Thrown like the water balloon; leaves an oil puddle where it lands (cars lose their grip).
static func _oil_slick() -> ItemDef:
	var d := _thrown(&"oil_slick", "Oil Slick", ItemDef.Kind.OIL, OIL_COLOR, 15.0, 10.0)
	d.explosion_radius = 3.0    # puddle radius
	return d

## Thrown like the water balloon; leaves a glue puddle where it lands (cars get very slow).
static func _sticky_glue() -> ItemDef:
	var d := _thrown(&"sticky_glue", "Sticky Glue", ItemDef.Kind.GLUE, GLUE_COLOR, 15.0, 10.0)
	d.explosion_radius = 2.8    # puddle radius
	return d

## Activated: every other car within the radius gets no drive (throttle, reverse, boost) for effect_time and its
## speed runs down to zero over that time.
static func _shocker() -> ItemDef:
	var d := _base(&"shocker", "Shocker", ItemDef.Kind.SHOCK, ItemDef.AimType.NONE, SHOCK_COLOR, 10.0, 15.0)
	d.explosion_radius = 8.0
	d.effect_time = 1.0
	return d

## Activated: blasts every other car within the radius away and up into the air.
static func _blast() -> ItemDef:
	var d := _base(&"blast", "Blast", ItemDef.Kind.BLAST, ItemDef.AimType.NONE, BLAST_COLOR, 0.0, 20.0)
	d.explosion_radius = 7.0
	d.knockback = 18.0
	d.up_knockback = 12.0
	return d

static func _thrown(id: StringName, display_name: String, kind: ItemDef.Kind, color: Color, w_leader: float,
		w_last: float) -> ItemDef:
	var d := _base(id, display_name, kind, ItemDef.AimType.LOB, color, w_leader, w_last)
	d.max_range = 18.0
	d.gravity = 25.0
	d.lifetime = 3.0
	d.effect_time = 10.0        # puddle lifetime
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
