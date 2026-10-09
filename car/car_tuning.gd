class_name CarTuning
extends Resource
## Every car feel number lives here. While the game runs, select a car in the Remote scene tree and edit `tuning` live.

@export_group("Body")
@export var mass: float = 150.0
@export var inertia: Vector3 = Vector3(60.0, 65.0, 40.0)   # x pitch, y yaw, z roll; high roll value = harder to flip
@export var center_of_mass: Vector3 = Vector3(0.0, -0.35, 0.0)
@export var gravity_scale: float = 2.0                      # arcade: heavier, snappier jumps
@export var max_angular_speed: float = 12.0
@export var linear_damp: float = 0.05
@export var angular_damp: float = 0.5
@export var body_friction: float = 0.1
@export var body_bounce: float = 0.15

@export_group("Suspension")
@export var wheel_mounts: PackedVector3Array = PackedVector3Array([
	Vector3(-0.5, -0.1, -0.7), Vector3(0.5, -0.1, -0.7),   # FL, FR
	Vector3(-0.5, -0.1, 0.7), Vector3(0.5, -0.1, 0.7)])    # RL, RR
@export var wheel_radius: float = 0.3
@export var suspension_rest_length: float = 0.35
@export var spring_strength: float = 4900.0   # N/m per wheel → ~0.15 m sag at mass 150, gravity ×2
@export var spring_damping: float = 450.0     # N·s/m per wheel, about half of critical

@export_group("Engine")
@export var max_speed: float = 18.0
@export var acceleration: float = 16.0
@export var reverse_max_speed: float = 11.0
@export var reverse_accel: float = 14.0
@export var brake_decel: float = 28.0
@export var rolling_decel: float = 3.0
@export var hold_brake_speed: float = 1.5
@export var hold_brake_max_accel: float = 14.0
@export var handbrake_decel: float = 6.0
@export var downforce_per_speed: float = 0.4
@export var direction_change_speed: float = 0.5   # |forward speed| below this counts as stopped when switching drive/reverse

@export_group("Grip and steering")
@export var front_grip: float = 0.85          # fraction of sideways velocity removed per tick
@export var rear_grip: float = 0.8
@export var drift_front_grip: float = 0.6
@export var drift_rear_grip: float = 0.12
@export var max_lateral_accel: float = 45.0   # caps grip per wheel → natural slide at speed
@export var grip_force_height: float = -0.2   # car-local y where grip is applied; lower = less body roll
@export var max_yaw_rate: float = 2.6         # rad/s at full steer
@export var yaw_response: float = 18.0
@export var full_steer_speed: float = 5.0
@export var min_steer_factor: float = 0.5
@export var high_speed_steer_mult: float = 0.75
@export var drift_yaw_mult: float = 1.4
@export var drift_lateral_accel_mult: float = 0.5   # grip cap while drifting (× max_lateral_accel): a bit like oil
@export var drift_yaw_response_mult: float = 0.5    # yaw held more loosely while drifting: rotates on a little
@export var drift_min_speed: float = 4.0         # a held-handbrake doughnut runs at ~5 m/s
@export var drift_slip_threshold: float = 1.2    # normal hard cornering slips ~0.5 m/s, handbrake slides > 1.3

@export_group("Directional drive (bots)")
@export var direction_deadzone: float = 0.2            # also the air-control input deadzone
@export var direction_full_steer_angle_deg: float = 50.0
@export var uturn_angle_deg: float = 110.0
@export var uturn_min_speed: float = 6.0
@export var uturn_throttle: float = 0.3        # throttle during the automatic handbrake U-turn
@export var tight_turn_throttle: float = 0.6   # throttle when the target is behind at low speed
@export var turn_throttle_min: float = 0.6     # throttle scale when the target is at the U-turn angle
@export var stuck_speed: float = 0.5           # below this while pushing forward counts as stuck
@export var stuck_time: float = 0.7
@export var auto_reverse_time: float = 0.8

@export_group("Battery and boost")
@export var start_battery: float = 0.3
@export var boost_accel: float = 20.0
@export var boost_speed_mult: float = 1.45
@export var boost_drain_rate: float = 0.4     # per second (battery is 0..1) → ~2.5 s of boost
@export var drift_charge_rate: float = 0.15   # ~7 s of drifting to fill
@export var air_charge_rate: float = 0.25
@export var air_charge_delay: float = 0.2
@export var pad_charge_rate: float = 0.3      # ~3 s on a pad to fill
@export var pad_max_speed: float = 1.5

@export_group("Air and landing")
@export var air_control_accel: float = 7.0
@export var air_control_needs_repress: bool = true   # keys already held at takeoff don't tilt until released and pressed again
@export var air_auto_level: float = 3.0
@export var air_angular_damp: float = 1.5
@export var min_air_time_for_landing: float = 0.35
@export var landing_window: float = 0.1          # all four wheels must touch down within this time
@export var perfect_landing_dot: float = 0.97    # up · ground normal at the first wheel contact (≈ 14° tolerance)
@export var landing_full_reward_air_time: float = 1.2   # airtime that earns the maximum landing reward
@export var landing_boost_min: float = 3.0       # forward push (m/s) at min_air_time_for_landing
@export var landing_boost_max: float = 9.0       # forward push (m/s) at landing_full_reward_air_time
@export var perfect_landing_battery_min: float = 0.05
@export var perfect_landing_battery_max: float = 0.2

@export_group("Hazards")
@export var wheel_coating_time: float = 5.0      # a wheel that touched oil / glue stays coated this long after leaving it
@export var oil_grip_mult: float = 0.05          # grip of an oiled wheel (fraction of normal)
@export var oil_lateral_accel_mult: float = 0.08 # an oiled wheel's grip cap (× max_lateral_accel): slides in turns and on slopes
@export var oil_brake_mult: float = 0.2          # braking and parking hold with all four wheels oiled (slides down slopes)
@export var oil_yaw_mult: float = 1.8            # yaw rate at full steer with all four wheels oiled (> 1: spins faster)
@export var oil_yaw_response_mult: float = 0.3   # how firmly the yaw rate is held on oil (low: keeps spinning after a turn)
@export var glue_speed_mult: float = 0.3         # top speed and acceleration with all four wheels glued
@export var glue_drag: float = 12.0              # extra deceleration (m/s²) above the glued top speed (all wheels)
@export_subgroup("Fluids")
@export var fluid_current_push: float = 1.5      # m/s² of push per m/s of a fluid's current (while touching)
@export var fluid_swim_min: float = 0.5          # body this far under (0..1) with wheels off the ground: paddle
@export var fluid_swim_accel: float = 0.35       # paddling: share of the normal acceleration
@export var fluid_angular_drag: float = 0.6      # share of a fluid's drag that also slows spinning

@export_group("Wall crash")
@export var wall_bounce_min_speed: float = 4.0   # impact speed (into the wall) needed for a kickback
@export var wall_bounce_factor: float = 0.6      # extra bounce-back speed per m/s of impact
@export var wall_bounce_pop: float = 0.45        # upward speed per m/s of impact (17 m/s head-on → ~0.7 m hop)
@export var wall_bounce_tumble: float = 0.02     # tip-away spin (rad/s) per m/s of impact
@export var wall_bounce_spin: float = 0.05       # max random yaw twist (rad/s) per m/s of impact
@export var wall_bounce_cooldown: float = 0.3
@export var wall_normal_max_y: float = 0.5       # contacts with steeper normals (floors, ramps) are not walls

@export_group("Bumping")
@export var bump_min_speed: float = 3.0
@export var bump_base: float = 4.0
@export var bump_speed_scale: float = 0.6
@export var bump_pop: float = 2.5
@export var bump_spin: float = 2.0
@export var bump_boost_mult: float = 1.6
@export var bump_cooldown: float = 0.35
@export var bump_score_strength: float = 7.0

@export_group("Recovery")
@export var flip_dot: float = 0.2
@export var flip_max_speed: float = 3.0       # only counts as stuck upside down below this speed
@export var flip_auto_time: float = 1.2
@export var reset_lift: float = 1.5
@export var reset_cooldown: float = 2.0
@export var kill_y: float = -15.0
