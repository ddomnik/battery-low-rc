# CLAUDE.md — Battery Low! (Godot 4.7 POC)

## Source of truth
- `docs/POC_SPEC.md` describes the whole POC. Read it fully before the first change and re-read the relevant section before each milestone.
- Work **one milestone at a time** (spec §9). When a milestone is done: run the checks below, fix everything they report, then write a short summary (what changed, any `# SPEC-QUESTION:` items, the acceptance checklist from the spec) and **stop** so the developer can playtest.

## Commands
- Import assets and surface parse errors:
  `godot --headless --path . --import`
- Headless smoke test of a match with bots (15 s of game time at a fixed 60 fps):
  `godot --headless --path . --fixed-fps 60 --quit-after 900 -- --autostart --bots=5`
- Normal run (developer playtest): `godot --path .`
- Treat any `SCRIPT ERROR`, `Parse Error`, `ERROR:` or `WARNING:` line that points at our scripts as a failure to fix before reporting done.
- If a Godot MCP server is connected, its run / debug-output tools may be used instead.

## Code rules
- Godot **4.7**, GDScript, **static typing everywhere** (typed vars, typed parameters and return types; `:=` only when the type is obvious).
- One class per file, `class_name` for shared types, snake_case file names, folder layout per spec §6.
- Keep `.tscn` files minimal (root node + script) and build children in code unless the spec says otherwise. Never write `uid=` attributes by hand; commit the generated `*.uid` files; never commit `.godot/`.
- All car feel numbers live in `CarTuning`. No magic numbers in car code.
- **Network-readiness rules (spec §4.3) are mandatory:** only `PlayerInput` reads `Input` / the mouse; gameplay state changes only when `Net.is_authority()`; gameplay randomness via `Match.rng`; never pause the SceneTree; effects via `Match.play_effect`.
- Never modify anything in `assets/kenney_car_kit/`.
- When the spec is ambiguous, choose the simplest option and leave a `# SPEC-QUESTION:` comment.

## Godot 3 → Godot 4 (avoid the left column)
| Godot 3 | Godot 4 |
|---|---|
| `Spatial`, `KinematicBody`, `RigidBody` | `Node3D`, `CharacterBody3D`, `RigidBody3D` |
| `export var`, `onready var`, `tool` | `@export var`, `@onready var`, `@tool` |
| `yield(obj, "sig")` | `await obj.sig` |
| `connect("sig", self, "_m")` | `sig.connect(_m)` |
| `scene.instance()` | `scene.instantiate()` |
| `translation` | `position` |
| `rand_range()` | `randf_range()` |
| `PoolVector3Array` | `PackedVector3Array` |
| `get_world()` | `get_world_3d()` |
| `array.empty()` | `array.is_empty()` |
| `space.intersect_ray(from, to, exclude)` | `space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask, exclude))` |
| `add_force(force, pos)` / `apply_impulse(pos, impulse)` | `apply_force(force, pos)` / `apply_impulse(impulse, pos)` |
| `setget` | `var x: int: set = _set_x` or inline `set(value):` |
| `OS.window_size` | `get_window().size` |
