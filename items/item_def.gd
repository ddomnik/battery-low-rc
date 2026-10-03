class_name ItemDef
extends Resource
## One item type. ItemRegistry builds them in code for now (move to .tres later).

enum Kind { BATTERY, ROCKET, BALLOON }
enum AimType { NONE, STRAIGHT, LOB }

@export var id: StringName
@export var display_name: String
@export var kind: Kind
@export var aim_type: AimType
@export var color: Color
@export var count: int = 1              # projectiles per use
@export var spread_deg: float = 0.0     # total fan between outer projectiles
@export var max_range: float = 22.0     # LOB only
@export var battery_amount: float = 0.5 # BATTERY only
@export var weight_leader: float = 0.0  # roll weight when this car is in 1st place
@export var weight_last: float = 0.0    # roll weight when this car is in last place

@export_group("Projectile")
@export var speed: float = 35.0         # STRAIGHT launch speed (m/s)
@export var max_pitch_deg: float = 25.0 # STRAIGHT pitch clamp
@export var gravity: float = 0.0        # m/s²
@export var lifetime: float = 3.0
@export var explosion_radius: float = 3.5
@export var knockback: float = 11.0     # horizontal velocity change (m/s) at the explosion center
@export var up_knockback: float = 4.0   # upward velocity change (m/s) at the center
@export var spin: float = 3.0           # max random yaw twist (rad/s) at the center
@export var tumble: float = 1.5         # tip-away spin (rad/s) at the center: the side facing the blast lifts
