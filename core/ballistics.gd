class_name Ballistics
## Launch helpers for projectiles and their aim previews.

static func lob_flight_time(distance: float, max_range: float) -> float:
	return lerpf(0.45, 1.0, clampf(distance / max_range, 0.0, 1.0))

## Launch velocity so a projectile under `gravity` travels from `from` to `to` in `t` seconds.
static func lob_velocity(from: Vector3, to: Vector3, gravity: float, t: float) -> Vector3:
	return (to - from) / t + Vector3.UP * (0.5 * gravity * t)

## Straight shot from `from` toward `to` at `speed`, with the pitch clamped to ±max_pitch_deg.
static func straight_velocity(from: Vector3, to: Vector3, speed: float, max_pitch_deg: float) -> Vector3:
	var d := to - from
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var max_pitch := deg_to_rad(max_pitch_deg)
	var pitch := clampf(atan2(d.y, flat.length()), -max_pitch, max_pitch)
	return (flat.normalized() * cos(pitch) + Vector3.UP * sin(pitch)) * speed

## Clamps the horizontal distance; if clamped, finds the surface height under the new point with a down-ray.
## Needs physics access: call from _physics_process only.
static func clamp_target(space: PhysicsDirectSpaceState3D, origin: Vector3, target: Vector3, max_range: float) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if flat.length() <= max_range:
		return target
	var p := origin + flat.normalized() * max_range
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 40.0, Layers.WORLD)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3(p.x, origin.y, p.z)
