# Battery Low! — POC Technical Implementation Spec

**Target:** Godot 4.7.x (standard build), GDScript · **Audience:** coding agent (Claude Code in VS Code) and the developer

> **For the agent:** This document is the source of truth for the proof of concept. Implement it milestone by milestone (§9). After each milestone, run the checks from `CLAUDE.md`, write a short summary plus the acceptance checklist for the developer, then stop and wait for playtest feedback.
> Code blocks are reference implementations. Adapt them where needed, but keep their behaviour, sign conventions and tuning hooks. If the spec is ambiguous, pick the simplest option and leave a `# SPEC-QUESTION:` comment.

---

## 0. Playtest decisions (override the sections below)

Decided by the developer during playtests. Where these conflict with later sections, these win.

**Car feel (M1)**
- Tuning: `reverse_max_speed` 11, `reverse_accel` 14, `max_yaw_rate` 2.6, `yaw_response` 18, `min_steer_factor` 0.5 (turn circle radius ~5.6 m from standstill, ~8.5 m at full speed; full turn rate within ~0.2 s at speed). Acceleration stays as specified.
- `_apply_grip` ignores the sideways wheel velocity caused by the car's own yaw rotation (otherwise grip brakes every turn and the car reaches only ~12 % of `max_yaw_rate`). Roll and pitch still count.
- The hold brake also cancels the slope pull (forward and sideways), so parked cars don't creep.
- Air control: an input axis already held at takeoff doesn't tilt the car until it is released and pressed again (`air_control_needs_repress`, default on).
- Drift detection for battery charge: `drift_min_speed` 4, `drift_slip_threshold` 1.2 (a held handbrake + steer settles into a ~5 m/s doughnut with ~1.4 m/s slip; normal hard cornering slips ~0.5 m/s).
- Perfect landing is skill-based: judged at the first wheel contact (up · ground normal ≥ 0.97, ≈ 14°), airtime ≥ 0.35 s, all four wheels within 0.1 s. Hands-off kicker jumps do not qualify; leveling with re-pressed W/S does.
- The perfect-landing reward grows with airtime: push 3 → 9 m/s and battery +5 % → +20 % between 0.35 s and 1.2 s of air (`landing_boost_min/max`, `perfect_landing_battery_min/max`, `landing_full_reward_air_time`).
- Wall crashes kick the car back: impact speed (into the wall) ≥ 4 m/s → extra bounce of 0.6 × impact, a 0.45 × impact hop (~0.7 m at 17 m/s), a slight tip-away spin and a small random yaw twist, sparks via `play_effect(&"bump")` and camera shake (impact / 30) for the local car ("Wall crash" group in `CarTuning`).
- Explosions also spin the car slightly: random yaw twist (`ItemDef.spin`, 3 rad/s at the center) and a tip-away tumble (`ItemDef.tumble`, 1.5 rad/s) so the side facing the blast lifts; both fall off with distance.
- Bumping (§7.3.6) reads the other car's velocity from *before* the collision was resolved (`Car.velocity_into_last_step()`), so a full-speed ram counts as full speed. With the spec's tuning this gives ~14.6 m/s at 18 m/s and ~27 m/s boosted.
- Boost visuals: blue exhaust cone (`car/exhaust.gdshader`, additive) plus blue sparks.

**Items (M4)**
- Explosions launch cars noticeably: water balloon `knockback` 13 / `up_knockback` 10, rockets 16 / 10 (linear falloff to the edge of the radius).
- Muzzle position is computed from the car transform and aim point (not the animated turret); projectiles follow the analytic parabola.
- Item boxes are magnetic: the nearest car with a free item slot within 7 m pulls the box like gravity (acceleration = 150 / distance², capped at 45 m/s², max 24 m/s). With nobody pulling, the box drifts back home at 4 m/s. After a pickup it reappears at its home spot after 6 s (`ItemBox` "Magnet" exports).

**Controls and camera (replaces screen-relative steering for players)**
- Players always use car-relative controls: W/S throttle (S brakes, then reverses), A/D steer. `CarInput.SteeringMode` is now `CarInput.DriveMode { DIRECTIONAL, CLASSIC }`; players send `CLASSIC`.
- `DIRECTIONAL` is the former screen-relative resolution (§7.3.3: steer toward `move_world`, automatic U-turn, stuck assist). It is used by bots (§7.7 "always SCREEN_RELATIVE" means `DIRECTIONAL`). A U-turn that starts below `uturn_min_speed` stays a tight turn.
- Two camera modes (`CameraRig.Mode`), purely local presentation:
  - **Follow** (default): the camera yaw smoothly swings behind the car's nose (`yaw_follow_sharpness`), holds while airborne or flipped, and does not swing when reversing.
  - **Classic**: fixed north-up camera (the original §7.4 behaviour).
- F2 (`debug_toggle_camera`) toggles the camera mode. It is persisted as `Settings.camera_mode` / `MatchConfig.camera_mode`. Menus (§7.1) offer "Camera: Follow (recommended) / Classic" instead of the steering option. The command-line flag is `--camera=follow|fixed` instead of `--steering=`.
- §5 "camera yaw is fixed at 0" applies to the Classic camera only.
- F11 toggles fullscreen anywhere (menus and matches); persisted as `Settings.fullscreen`.

**Scoring (M6)**
- Knockout: when a car falls off the map (below `kill_y`), the car that last bumped or blasted it within 6 s gets +10 points and a "KNOCKOUT!" popup. Falling off alone scores nothing. Every car (bots included) then respawns at the spawn point farthest from the others.

**M2 acceptance (replaces §9 M2)**
- [ ] Follow camera swings smoothly behind the car (lazy, not rigid), settles when driving straight, doesn't swing when reversing or in the air.
- [ ] W always drives "up the screen" once the camera has settled.
- [ ] F2 switches to the fixed north-up camera and back, smoothly; the choice persists across matches.
- [ ] Controls are identical in both camera modes.

---

## 1. What the POC proves

A top-down party vehicle brawler: small cars in an arena, a fixed-angle camera like an RTS, WASD driving, mouse-aimed items. No racing. Up to 10 cars (1 human plus bots in the POC).

**In scope**
1. Camera: fixed view angle, lazy follow, look-ahead toward velocity and cursor.
2. Driving: arcade raycast-suspension car on a RigidBody3D, including slopes, jumps and drifting. Two steering schemes (screen-relative and classic), switchable.
3. Game flow: main menu → match → in-game menu → exit to main menu (not quitting the app). Restart. Results screen.
4. Picking up items from item boxes, with a catch-up roll based on rank.
5. Mouse aiming: reticle on the surface under the cursor, roof turret, straight and lobbed projectiles.
6. Battery as boost meter (charged by drifting, airtime and charging pads), air control, perfect-landing mini-boost, flip recovery.
7. Bumping: heavy knockback between cars; scoring hits.
8. Simple bots, so bumping and ranks can be tested alone.

**Out of scope, but the architecture must allow it**
Networking (LAN first, internet later), more modes (Balloon Battle, Hot Potato, …), real arenas/art, audio, gamepad (input structure ready), occlusion cutout (§10, optional M7).

---

## 2. Developer setup (do this before handing over to the agent)

1. **Install Godot 4.7.x, standard build (GDScript), not the .NET build.** On Windows, keep the `..._console.exe` that ships next to the editor; it prints to the terminal and is the one to use on the command line.
2. **Create the project with the Project Manager:** name `battery-low`, renderer **Forward+**, version control metadata **Git**. New projects created with Godot 4.6+ already use Jolt Physics.
3. **Copy the Kenney Car Kit** into the project:
   - Copy the folder `Models/GLB format/` from the extracted kit to `res://assets/kenney_car_kit/`, plus `License.txt`.
   - If the GLB folder references a `Textures/` folder (open a `.glb` in Godot: magenta or untextured means the texture is missing), copy that next to it too.
   - Open the editor once so everything gets imported.
4. **VS Code:** install the extension **godot-tools**. In Godot: *Editor → Editor Settings → Text Editor → External*: enable *Use External Editor*, set *Exec Path* to VS Code, *Exec Flags* to `{project} --goto {file}:{line}:{col}`. The GDScript language server only works while the Godot editor is open.
5. **Command line:** make `godot` runnable from a terminal (add to PATH or create an alias pointing to the console executable). Test with `godot --version`.
6. **Optional, recommended:** a Godot MCP server so the agent can run the project and read errors itself:
   `claude mcp add godot -e GODOT_PATH=/path/to/godot -- npx @coding-solo/godot-mcp` (needs Node.js).
7. Put this file at `docs/POC_SPEC.md` and the provided `CLAUDE.md` in the project root. Commit.

---

## 3. Project settings (agent applies; developer can verify with *Advanced Settings* on)

| Setting | Value | Why |
|---|---|---|
| `application/run/main_scene` | `res://main/main.tscn` | |
| `display/window/size/viewport_width` / `_height` | 1600 / 900 | |
| `display/window/stretch/mode` / `aspect` | `canvas_items` / `expand` | UI scales cleanly |
| `physics/3d/physics_engine` | `Jolt Physics` | default for new projects, verify |
| `physics/common/physics_ticks_per_second` | 60 | try 120 if suspension jitters |
| `physics/common/physics_interpolation` | `true` | smooth on 144 Hz monitors |
| `physics/common/physics_jitter_fix` | `0.0` | recommended with interpolation |
| `rendering/anti_aliasing/quality/msaa_3d` | 4× (value `2`) | crisp low-poly edges from above |
| `layer_names/3d_physics/layer_1..5` | `world`, `cars`, `pickups`, `projectiles`, `triggers` | |
| `layer_names/3d_render/layer_1..2` | `world`, `cars` | blob shadow must not draw on cars |
| Autoloads (in this order) | `Settings`, `InputSetup`, `Net`, `Game` | §7.1 |

---

## 4. Architecture

### 4.1 Runtime scene tree

```
Main (main.gd)                          persistent root scene, never replaced
├── WorldRoot (Node3D)                  holds the active Match (or nothing)
│   └── Match (match.gd)
│       ├── Arena (test_arena.gd)       geometry, light, environment, spawn markers, pads
│       ├── ItemBoxes (Node3D)
│       ├── Cars (Node3D)
│       │   └── Car_<player_id> (car.gd, RigidBody3D)  × N
│       │       ├── CollisionShape3D
│       │       └── Visual (car_visual.gd)   Kenney model, wheels, turret, ring, label, shadow, particles
│       ├── Projectiles (Node3D)
│       ├── Effects (Node3D)
│       ├── Inputs (Node)               PlayerInput, BotInput × N
│       ├── CameraRig (camera_rig.gd)
│       │   └── Camera3D
│       ├── AimVisuals (aim_visuals.gd) local player only: reticle, lob arc
│       ├── DebugDraw (debug_draw.gd)
│       └── UI (CanvasLayer)            HUD, InGameMenu, Results, DebugOverlay
└── UIRoot (CanvasLayer)                MainMenu lives here while no match runs
```

### 4.2 Order of operations per physics tick

1. `PlayerInput._physics_process` / `BotInput._physics_process` (both `process_physics_priority = -10` so they run first): read keys or AI, raycast the mouse to get `aim_point`, build a `CarInput`.
2. `Car._physics_process`: pull its `CarInput` from its provider, run game logic (battery, boost flag, item use, reset/respawn requests, forward queued events to Match).
3. Physics step → `Car._integrate_forces(state)`: wheel raycasts, suspension, drive, grip, yaw, air control, landing detection, bump detection.
4. Each rendered frame (`_process`): CameraRig follows the interpolated car transform; visuals update wheels, turret, particles; HUD updates.

### 4.3 Network-readiness rules (mandatory even though the POC is offline)

1. **Only `PlayerInput` reads `Input` or the mouse.** All gameplay code, including the car, consumes `CarInput` only.
2. `CarInput` is in **world space** (move direction as a world vector, aim as a world position), so a server never needs the client's camera. Implement `to_dict()` / `from_dict()` now.
3. **Authority:** every gameplay state change (forces, scores, item rolls, pickups, knockback, spawns) runs only if `Net.is_authority()` (wraps `multiplayer.is_server()`, which is `true` in offline mode).
4. **Gameplay randomness** only through `Match.rng` (`RandomNumberGenerator`, seeded at match start).
5. **Never pause the SceneTree.** The in-game menu is an overlay.
6. Players are identified by `player_id: int` and `peer_id: int`, never by node references across "the wire". Car nodes are named `Car_%d` % player_id.
7. **Cosmetic effects** go through one choke point, `Match.play_effect(kind, position, param)`, which later becomes an RPC.
8. **Spawning** goes through `Match.spawn_car(info)` and `Match.spawn_projectile(...)`, which later get wrapped by `MultiplayerSpawner`.

---

## 5. Conventions

- **Units:** meters, seconds, kilograms. A car is about 2 m long; that size is physics-friendly. The "toy" scale is purely an art choice later: the world objects get big, the cars don't get small.
- **Axes:** +Y up, car forward = `-global_basis.z`, car right = `+global_basis.x`.
- **Map orientation:** north = −Z. The camera yaw is fixed at 0, so screen-up = north, screen-right = +X.
- **Steering sign:** `steer = +1` means turn **left** = counter-clockwise seen from above = positive rotation around +Y. This matches `Vector3.signed_angle_to(…, Vector3.UP)` and `angular_velocity.dot(up)`.
- **Battery:** float 0..1.
- **Wheel order:** 0 = front-left, 1 = front-right, 2 = rear-left, 3 = rear-right.

### 5.1 Physics layers (`layers.gd`, `class_name Layers`)

```gdscript
class_name Layers
const WORLD := 1        # layer 1: static geometry
const CARS := 2         # layer 2: car bodies
const PICKUPS := 4      # layer 3: item boxes (Area3D)
const PROJECTILES := 8  # layer 4: reserved (projectiles use manual sweeps)
const TRIGGERS := 16    # layer 5: charging pads (Area3D)
const RENDER_WORLD := 1 # render layer 1
const RENDER_CARS := 2  # render layer 2
```

| Object | collision_layer | collision_mask |
|---|---|---|
| Static world | WORLD | 0 |
| Car body | CARS | WORLD \| CARS |
| ItemBox (Area3D) | PICKUPS | CARS |
| ChargingPad (Area3D) | TRIGGERS | CARS |
| Wheel raycasts | — | WORLD |
| Mouse aim raycast | — | WORLD \| CARS |
| Projectile sweep | — | WORLD \| CARS |

### 5.2 Input actions (registered in code by `InputSetup`, using **physical** keycodes so German QWERTZ keyboards work)

| Action | Keys | Notes |
|---|---|---|
| `move_up` / `move_down` / `move_left` / `move_right` | W / S / A / D and arrow keys | |
| `handbrake` | Space | |
| `boost` | Shift (left) | |
| `fire` | Left mouse button | |
| `reset` | R | flip back onto wheels |
| `pause` | Escape | in-game menu |
| `debug_toggle_steering` | F2 | debug builds only |
| `debug_overlay` | F3 | |
| `debug_draw` | F4 | wheel rays, forces |
| `debug_fill_battery` | F6 | |
| `debug_add_score` | F7 | test catch-up |
| `debug_give_item_1..4` | 1–4 | |

```gdscript
extends Node
## InputSetup autoload: registers actions in code so nobody has to hand-edit serialized events in project.godot.

const KEYS := {
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE], "boost": [KEY_SHIFT], "reset": [KEY_R], "pause": [KEY_ESCAPE],
	"debug_toggle_steering": [KEY_F2], "debug_overlay": [KEY_F3], "debug_draw": [KEY_F4],
	"debug_fill_battery": [KEY_F6], "debug_add_score": [KEY_F7],
	"debug_give_item_1": [KEY_1], "debug_give_item_2": [KEY_2],
	"debug_give_item_3": [KEY_3], "debug_give_item_4": [KEY_4],
}
const MOUSE := {"fire": [MOUSE_BUTTON_LEFT]}

func _ready() -> void:
	for action: String in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in MOUSE:
		_ensure(action)
		for button: MouseButton in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)

func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
```

---

## 6. Folder structure

```
res://
├── project.godot
├── CLAUDE.md
├── docs/POC_SPEC.md
├── assets/kenney_car_kit/          (GLB files, Textures/ if needed, License.txt; never modify)
├── autoload/
│   ├── settings.gd                 persisted user settings (user://settings.cfg)
│   ├── input_setup.gd
│   ├── net.gd                      authority helpers; later host/join
│   └── game.gd                     app state machine, start/exit/restart match
├── core/
│   ├── layers.gd
│   ├── match_config.gd
│   └── ballistics.gd
├── main/
│   ├── main.tscn / main.gd
├── ui/
│   ├── main_menu.tscn / .gd
│   ├── hud.tscn / .gd
│   ├── ingame_menu.tscn / .gd
│   ├── results.tscn / .gd
│   └── debug_overlay.gd
├── match/
│   ├── match.tscn / match.gd
│   ├── effects.gd                  play_effect implementations
│   └── debug_draw.gd
├── arena/
│   ├── arena_builder.gd            static helpers: box, wedge, materials
│   ├── test_arena.tscn / test_arena.gd
│   ├── charging_pad.gd
│   └── shaders/checker.gdshader
├── car/
│   ├── car.tscn / car.gd
│   ├── car_tuning.gd
│   ├── car_input.gd
│   ├── car_visual.gd
│   ├── player_input.gd
│   └── bot_input.gd
├── camera/
│   ├── camera_rig.tscn / camera_rig.gd
│   └── aim_visuals.gd
└── items/
    ├── item_def.gd
    ├── item_registry.gd
    ├── item_box.gd
    └── projectile.gd
```

Prefer `.tscn` files that contain only the root node plus script, and build children in code. Hand-written scene files are a frequent source of breakage.

---

## 7. Systems

### 7.1 Game flow

**Settings (autoload):** holds `steering_mode`, `bot_count`, `player_name`; loads/saves `user://settings.cfg` with `ConfigFile`.

**Net (autoload), POC stub:**
```gdscript
extends Node
## Transport lives here only. POC: the default OfflineMultiplayerPeer → we are server, peer id 1.
func is_authority() -> bool:
	return multiplayer.is_server()
func local_peer_id() -> int:
	return multiplayer.get_unique_id()
# Later: host_lan(port), join_lan(address, port) using ENetMultiplayerPeer; LAN discovery via UDP broadcast.
```

**MatchConfig (`RefCounted`):** `bot_count: int = 5` (0..9), `steering_mode: CarInput.SteeringMode`, `round_time: float = 180.0`, `player_name: String`, `seed: int = 0` (0 = random), `car_model_path: String = ""` (empty = auto).

**Game (autoload) API:**
- `start_match(config: MatchConfig)` → `Main.show_match(config)`
- `exit_to_menu()` → `Main.show_menu()`, `Input.mouse_mode = Input.MOUSE_MODE_VISIBLE`
- `restart_match()` → exit and start again with the same config (exercises the cleanup path)
- `quit_app()` → `get_tree().quit()` (only from the main menu)
- **Command-line autostart** for headless smoke tests: in `_ready` (deferred), parse `OS.get_cmdline_user_args()`; `--autostart` starts a match immediately; `--bots=N`, `--steering=classic|screen`, `--round=SECONDS` override config.

**Main (`main.gd`):** registers itself with `Game` on `_ready`. `show_match` frees whatever is in `WorldRoot` and `UIRoot`, instantiates `match.tscn`, calls `match.setup(config)`. `show_menu` frees the match and instantiates the main menu.

**Main menu:** title "BATTERY LOW!", buttons/fields: **Play**, **Bots** (SpinBox 0–9), **Steering** (OptionButton: "Screen-relative (recommended)" / "Classic"), **Quit**. Values persist through `Settings`.

**Match states:**
| State | Duration | Behaviour |
|---|---|---|
| `COUNTDOWN` | 3 s | cars `frozen` (neutral input, hold brake), big "3 · 2 · 1 · GO!" |
| `PLAYING` | `round_time` | timer counts down |
| `RESULTS` | until button | cars frozen, ranked list, buttons **Play again** / **Exit to menu** |

**Match responsibilities (`match.gd`):**
- `setup(config)`: seed `rng` (`config.seed` or random), instance the arena, spawn cars, create item boxes at `item_spawn` markers, set `camera_rig.target` to the local car and call `snap_to_target()`, bind the HUD, enter `COUNTDOWN`.
- `spawn_car(info)`: `info = {player_id, peer_id, name, color, is_bot, model_path}`. The local player is `player_id = 1`, bots are `2..N`, named "Bot 1…". Colors from a fixed 10-color palette (red, blue, yellow, green, orange, purple, cyan, pink, lime, white). Place at a spawn point, set `battery = tuning.start_battery`, create the input provider (`PlayerInput` or `BotInput`) under `Inputs`, connect `item_used`, `bumped`, `perfect_landing`, `respawn_requested`.
- Keeps `cars: Array[Car]`, `scores: Dictionary` (player_id → int), `item_defs: Array[ItemDef]`, `rng`.
- `respawn(car)`: ignore repeated requests for the same car within 0.5 s; pick the spawn point farthest from other cars; `car.teleport_to(...)`; clear its velocity through the teleport.
- Sets `car.frozen` per state; switches mouse mode; owns the in-game menu and results screen.
- `play_effect(kind, pos, param)`, `register_hit(attacker, victim)`, `roll_item(car)`, `explode(...)`, `spawn_projectile(...)` (§7.6).

**In-game menu (Escape):** Resume, Restart, Steering mode toggle, Exit to menu. It does **not** pause the tree; while open, the local `PlayerInput.enabled = false` (car coasts and holds still) and the mouse is visible.

**Mouse modes:** `MOUSE_MODE_CONFINED_HIDDEN` while playing (a small 2D crosshair Control follows the mouse, plus the 3D reticle), `MOUSE_MODE_VISIBLE` in any menu.

**Cleanup requirement:** after "Exit to menu", `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` must return to its pre-match value. Show it in the debug overlay and on the main menu in debug builds.

### 7.2 Test arena

Built in code by `test_arena.gd` using static helpers in `arena_builder.gd`. Optionally mark the script `@tool` and build in `_ready` without setting `owner`, so the geometry is visible in the editor but not saved into the scene.

**Helpers**
```gdscript
class_name ArenaBuilder
## box(): StaticBody3D + MeshInstance3D(BoxMesh) + CollisionShape3D(BoxShape3D).
static func box(parent: Node3D, center: Vector3, size: Vector3, color: Color, yaw_deg: float = 0.0) -> StaticBody3D:
	pass # implement

## wedge(): triangular prism. Footprint size.x (width) × size.z (length), height size.y.
## In local space it rises toward −Z: low edge at z = +L/2 (y = 0), high edge at z = −L/2 (y = H).
## yaw_deg rotates it around Y (0 = rises toward north, 90 = rises toward west, 180 = south, −90 = east).
## Collision: ConvexPolygonShape3D from the 6 corner points. Mesh: SurfaceTool, flat normals
## (st.set_smooth_group(-1) then st.generate_normals()). Slope angle = atan(H / L).
static func wedge(parent: Node3D, base_center: Vector3, size: Vector3, yaw_deg: float, color: Color) -> StaticBody3D:
	pass # implement
```
All static bodies: `collision_layer = Layers.WORLD`, `collision_mask = 0`. Cache one `StandardMaterial3D` per color (roughness 0.8). Toy palette: `#FF595E`, `#FFCA3A`, `#8AC926`, `#1982C4`, `#6A4C93`, `#FF924C`, `#4CC9F0`.

**Floor shader (`checker.gdshader`)**, a world-space checker so speed is readable from above:
```glsl
shader_type spatial;
uniform vec3 color_a : source_color = vec3(0.93, 0.87, 0.75);
uniform vec3 color_b : source_color = vec3(0.86, 0.79, 0.66);
uniform float cell = 2.0;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(world_pos.xz / cell);
	ALBEDO = mix(color_a, color_b, mod(c.x + c.y, 2.0));
	ROUGHNESS = 0.9;
}
```

**Layout** (north = −Z; adjust positions if anything overlaps):

| Element | Placement | Purpose |
|---|---|---|
| Floor | box center (0, −0.5, 0), size 90 × 1 × 90, checker | |
| Walls N / E / W | thickness 1, height 1.5, at the edges (±45) | |
| Wall S (camera side) | height 0.6 | barely occludes |
| Table | box center (0, 1.5, −12), size 20 × 3 × 12 (top at y = 3, z from −18 to −6) | raised platform |
| Ramp A, gentle 14° | wedge W6 H3 L12, rises north, footprint x −3..3, z +6..−6, ends at table's south face | |
| Ramp B, medium 25° | wedge W6 H3 L6.4, rises west, footprint x 16.4..10, centered z = −12 | slope test |
| Ramp C, steep 35° | wedge W6 H3 L4.3, rises east, footprint x −14.3..−10, centered z = −12 | slope test |
| Table north edge | open drop | fall-off test |
| Kicker 17° | wedge W5 H1.2 L4 at x = −25, footprint z 22..18, rises north; keep z 18..0 clear for landing | jump, air control, perfect landing |
| Humps | at x = 38, width 6: four pairs of wedges (up H1 L4 rising north, then down H1 L4 rising south), pairs starting at z = 20, 10, 0, −10 | suspension |
| Side slope ~12° | wedge W12 H2.5 L12, rises east, footprint x 22..34, z −38..−26 | driving across a slope |
| Cubes 2 × 2 × 2 | (−15, 1, 5), (15, 1, 8), (−36, 1, 0), (5, 1, 25), (−8, 1, 32), (30, 1, −14), (−38, 1, 25), (12, 1, −30) | bump into |
| Pillars 2 × 6 × 2 | (−12, 3, 38), (12, 3, 38) | occlusion test (M7) |
| Charging pads | (−36, 0, −36) and (36, 0, 36), 5 × 5 | |
| Item boxes | 8 on a circle r = 24 (every 45°), plus (0, 3.8, −12) on the table, plus (−25, 0.8, 8) in the kicker landing zone | |
| Spawn points | 10 on a circle r = 32, facing the center (`Marker3D`, group `spawn_point`) | |
| Kill height | y < −15 → respawn | |

Item spawn markers go in group `item_spawn`; Match instantiates the `ItemBox`es.

**Light and environment:** `DirectionalLight3D` rotated about (−55°, 35°, 0), shadows on, `directional_shadow_max_distance` 90. `WorldEnvironment`: procedural sky, ambient light from sky (energy ~0.6), tonemap AgX, optional SSAO.

### 7.3 Car

#### 7.3.1 Scene and body setup

`car.tscn`: `RigidBody3D` root with `car.gd`, child `CollisionShape3D` (`BoxShape3D` size 1.1 × 0.5 × 2.0 centered at the origin, bottom at y = −0.25), child `Visual` (`Node3D` with `car_visual.gd`). Everything else is built in code.

In `_ready`, apply from `tuning` (create `CarTuning.new()` if none is assigned):
`mass`, `center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM`, `center_of_mass`, `inertia` (set explicitly so torque formulas stay predictable), `gravity_scale`, `can_sleep = false`, `contact_monitor = true`, `max_contacts_reported = 8`, `linear_damp_mode`/`angular_damp_mode = DAMP_MODE_REPLACE` with `linear_damp = 0.05`, `angular_damp = 0.5`, `physics_material_override` (friction 0.1, bounce 0.15), layers per §5.1.

**Geometry at rest:** wheel mounts at y = −0.1, rest length 0.35, wheel radius 0.3, sag about 0.15 m. The ground therefore sits at about y = −0.6 in car space, and the chassis box bottom (−0.25) floats about 0.35 m above it. Only the raycasts touch the ground.

#### 7.3.2 CarInput

```gdscript
class_name CarInput
extends RefCounted
## One tick of intent. Produced by PlayerInput (local), BotInput (AI) or, later, received over the network.

enum SteeringMode { SCREEN_RELATIVE, CLASSIC }

var steering_mode: SteeringMode = SteeringMode.SCREEN_RELATIVE
var move_world: Vector3 = Vector3.ZERO   # SCREEN_RELATIVE: desired direction on the XZ plane, length 0..1
var throttle: float = 0.0                # CLASSIC: -1..1 (+ = forward)
var steer: float = 0.0                   # CLASSIC: -1..1 (+ = left / counter-clockwise)
var handbrake: bool = false
var boost: bool = false
var fire: bool = false                   # one-tick pulse; producer latches until consumed
var reset: bool = false                  # one-tick pulse
var aim_point: Vector3 = Vector3.ZERO    # world position under the cursor (or bot target)

static func neutral(keep_aim: Vector3 = Vector3.ZERO) -> CarInput:
	var i := CarInput.new()
	i.aim_point = keep_aim
	return i

func to_dict() -> Dictionary:
	return {"m": steering_mode, "mw": move_world, "t": throttle, "s": steer,
		"hb": handbrake, "b": boost, "f": fire, "r": reset, "a": aim_point}

static func from_dict(d: Dictionary) -> CarInput:
	var i := CarInput.new()
	i.steering_mode = d.get("m", SteeringMode.SCREEN_RELATIVE)
	i.move_world = d.get("mw", Vector3.ZERO)
	i.throttle = d.get("t", 0.0)
	i.steer = d.get("s", 0.0)
	i.handbrake = d.get("hb", false)
	i.boost = d.get("b", false)
	i.fire = d.get("f", false)
	i.reset = d.get("r", false)
	i.aim_point = d.get("a", Vector3.ZERO)
	return i
```

#### 7.3.3 Drive resolution (turns CarInput into throttle/steer/handbrake)

Screen-relative steering: the pressed direction is a world direction; the car steers toward it at its normal turning rate, keeps momentum and can drift. Pressing the opposite direction at speed triggers an automatic handbrake U-turn. A stuck assist reverses out of walls.

```gdscript
class DriveCommand:
	var throttle: float = 0.0   # -1..1
	var steer: float = 0.0      # -1..1, + = left
	var handbrake: bool = false

func _resolve_drive(fwd: Vector3, dt: float) -> DriveCommand:
	var d := DriveCommand.new()
	d.handbrake = _input.handbrake
	if _input.steering_mode == CarInput.SteeringMode.CLASSIC:
		d.throttle = _input.throttle
		d.steer = _input.steer
		return d

	var want := Vector3(_input.move_world.x, 0.0, _input.move_world.z)
	var amount := minf(want.length(), 1.0)
	if amount < tuning.screen_deadzone:
		_stuck_timer = 0.0
		_auto_reverse_timer = 0.0
		return d
	want /= want.length()
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length_squared() < 0.01:
		return d  # car is vertical; air control / recovery handles it
	fwd_flat = fwd_flat.normalized()

	var angle := fwd_flat.signed_angle_to(want, Vector3.UP)  # + = target is to the left
	var abs_angle := absf(angle)
	var uturn := deg_to_rad(tuning.uturn_angle_deg)
	d.steer = clampf(angle / deg_to_rad(tuning.screen_full_steer_angle_deg), -1.0, 1.0)
	if abs_angle > uturn:
		if forward_speed > tuning.uturn_min_speed:
			d.throttle = 0.3
			d.handbrake = true          # automatic handbrake U-turn
		else:
			d.throttle = 0.6            # tight low-speed turn
	else:
		d.throttle = amount * lerpf(1.0, 0.6, abs_angle / uturn)

	# Stuck assist: pushing forward without moving → reverse briefly; reversed steering swings the nose toward the target.
	if _auto_reverse_timer > 0.0:
		_auto_reverse_timer -= dt
		d.throttle = -1.0
		d.steer = -d.steer
		d.handbrake = false
	elif d.throttle > 0.0 and absf(forward_speed) < 0.5:
		_stuck_timer += dt
		if _stuck_timer > tuning.stuck_time:
			_stuck_timer = 0.0
			_auto_reverse_timer = tuning.auto_reverse_time
	else:
		_stuck_timer = 0.0
	return d
```

#### 7.3.4 Physics core (`car.gd`)

```gdscript
class_name Car
extends RigidBody3D

signal battery_changed(value: float)
signal item_changed(item: ItemDef)
signal item_used(car: Car, item: ItemDef, aim_point: Vector3)
signal perfect_landing(car: Car)
signal bumped(car: Car, attacker: Car, strength: float)
signal respawn_requested(car: Car)

const WHEELS := 4

@export var tuning: CarTuning

var player_id: int = 0
var peer_id: int = 1
var display_name: String = "Player"
var color: Color = Color.WHITE
var input_provider: Object = null   # implements get_car_input(car: Car) -> CarInput

var battery: float = 0.0
var held_item: ItemDef = null
var is_boosting: bool = false
var is_drifting: bool = false
var frozen: bool = true
var pad_overlaps: int = 0

# Read-only caches for visuals, HUD, debug, bots.
var grounded_count: int = 0
var forward_speed: float = 0.0
var lateral_speed: float = 0.0
var air_time: float = 0.0
var last_steer: float = 0.0
var last_aim_point: Vector3 = Vector3.ZERO
var wheel_grounded: Array[bool] = [false, false, false, false]
var wheel_spring_len: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _input: CarInput = CarInput.new()
var _drive: DriveCommand = DriveCommand.new()
var _ground_normal: Vector3 = Vector3.UP
var _was_airborne: bool = false
var _landing_window: float = 0.0
var _pending_landing_reward: bool = false
var _pending_bumps: Array[Dictionary] = []
var _pending_teleport: Variant = null       # Transform3D or null
var _bump_cooldowns: Dictionary = {}        # other car instance id -> seconds left
var _stuck_timer: float = 0.0
var _auto_reverse_timer: float = 0.0
var _upside_down_time: float = 0.0
var _reset_cooldown: float = 0.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not Net.is_authority():
		return
	if _pending_teleport != null:
		state.transform = _pending_teleport
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_teleport = null
		reset_physics_interpolation.call_deferred()
		return

	var dt := state.step
	var xf := state.transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var right := xf.basis.x

	_sample_wheels(state, xf, up)
	forward_speed = state.linear_velocity.dot(fwd)
	lateral_speed = state.linear_velocity.dot(right)
	_drive = _resolve_drive(fwd, dt)
	last_steer = _drive.steer

	_apply_suspension(state, xf, up)
	if grounded_count >= 2:
		_apply_drive(state, fwd, dt)
		_apply_grip(state, xf, right, up, dt)
		_apply_yaw(state, up)
		state.apply_central_force(-_ground_normal * tuning.downforce_per_speed * absf(forward_speed) * mass)
	elif grounded_count == 0:
		_apply_air_control(state, xf)
	_update_landing(state, xf, fwd, dt)
	_detect_bumps(state)
	if state.angular_velocity.length() > tuning.max_angular_speed:
		state.angular_velocity = state.angular_velocity.normalized() * tuning.max_angular_speed

func _sample_wheels(state: PhysicsDirectBodyState3D, xf: Transform3D, up: Vector3) -> void:
	var space := state.get_space_state()
	var ray_len := tuning.suspension_rest_length + tuning.wheel_radius
	var normal_sum := Vector3.ZERO
	grounded_count = 0
	for i in WHEELS:
		var from: Vector3 = xf * tuning.wheel_mounts[i]
		var query := PhysicsRayQueryParameters3D.create(from, from - up * ray_len, Layers.WORLD, [get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			wheel_grounded[i] = false
			wheel_spring_len[i] = tuning.suspension_rest_length
			continue
		wheel_grounded[i] = true
		grounded_count += 1
		var hit_pos: Vector3 = hit.position
		wheel_spring_len[i] = clampf(from.distance_to(hit_pos) - tuning.wheel_radius, 0.0, tuning.suspension_rest_length)
		normal_sum += hit.normal
	_ground_normal = normal_sum.normalized() if grounded_count > 0 else Vector3.UP

func _apply_suspension(state: PhysicsDirectBodyState3D, xf: Transform3D, up: Vector3) -> void:
	for i in WHEELS:
		if not wheel_grounded[i]:
			continue
		# apply_force's position is an offset from the body origin in GLOBAL orientation, not a world position.
		var offset: Vector3 = xf.basis * tuning.wheel_mounts[i]
		var compression := tuning.suspension_rest_length - wheel_spring_len[i]
		var spring_vel := state.get_velocity_at_local_position(offset).dot(up)
		var force := tuning.spring_strength * compression - tuning.spring_damping * spring_vel
		if force > 0.0:
			state.apply_force(up * force, offset)

func _apply_drive(state: PhysicsDirectBodyState3D, fwd: Vector3, dt: float) -> void:
	var fwd_g := (fwd - _ground_normal * fwd.dot(_ground_normal)).normalized()  # follows slopes
	var max_speed := tuning.max_speed * (tuning.boost_speed_mult if is_boosting else 1.0)
	var t := _drive.throttle
	var accel := 0.0
	if t > 0.01:
		if forward_speed < -0.5:
			accel = tuning.brake_decel
		else:
			accel = tuning.acceleration * t * clampf(1.0 - forward_speed / max_speed, 0.0, 1.0)
	elif t < -0.01:
		if forward_speed > 0.5:
			accel = -tuning.brake_decel
		else:
			accel = -tuning.reverse_accel * -t * clampf(1.0 + forward_speed / tuning.reverse_max_speed, 0.0, 1.0)
	elif absf(forward_speed) < tuning.hold_brake_speed:
		# Hold brake: cancel residual speed so the car parks on slopes.
		accel = clampf(-forward_speed / dt, -tuning.hold_brake_max_accel, tuning.hold_brake_max_accel)
	else:
		accel = -signf(forward_speed) * tuning.rolling_decel
	if _drive.handbrake:
		accel -= signf(forward_speed) * minf(tuning.handbrake_decel, absf(forward_speed) / dt)
	if is_boosting:
		accel += tuning.boost_accel * clampf(1.0 - forward_speed / max_speed, 0.0, 1.0)
	state.apply_central_force(fwd_g * accel * mass)

func _apply_grip(state: PhysicsDirectBodyState3D, xf: Transform3D, right: Vector3, up: Vector3, dt: float) -> void:
	var wheel_mass := mass / WHEELS
	var max_force := wheel_mass * tuning.max_lateral_accel
	for i in WHEELS:
		if not wheel_grounded[i]:
			continue
		var front := i < 2
		var grip := tuning.front_grip if front else tuning.rear_grip
		if _drive.handbrake:
			grip = tuning.drift_front_grip if front else tuning.drift_rear_grip
		var offset: Vector3 = xf.basis * tuning.wheel_mounts[i]
		var lat_vel := state.get_velocity_at_local_position(offset).dot(right)
		var force := clampf(-lat_vel * grip * wheel_mass / dt, -max_force, max_force)
		# Apply at a fixed low height to avoid grip-induced rollovers.
		var apply_at := offset - up * offset.dot(up) + up * tuning.grip_force_height
		state.apply_force(right * force, apply_at)

func _apply_yaw(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	var speed_abs := absf(forward_speed)
	var factor := clampf(speed_abs / tuning.full_steer_speed, 0.0, 1.0)
	if absf(_drive.throttle) > 0.01:
		factor = maxf(factor, tuning.min_steer_factor)   # can turn while pulling away
	factor *= lerpf(1.0, tuning.high_speed_steer_mult, clampf(speed_abs / tuning.max_speed, 0.0, 1.0))
	var reversing := forward_speed < -0.5 or (_drive.throttle < 0.0 and forward_speed < 0.5)
	var target := _drive.steer * tuning.max_yaw_rate * factor * (-1.0 if reversing else 1.0)
	if _drive.handbrake:
		target *= tuning.drift_yaw_mult
	var yaw_rate := state.angular_velocity.dot(up)
	state.apply_torque(up * (target - yaw_rate) * tuning.yaw_response * tuning.inertia.y)

func _apply_air_control(state: PhysicsDirectBodyState3D, xf: Transform3D) -> void:
	var inertia_avg := (tuning.inertia.x + tuning.inertia.y + tuning.inertia.z) / 3.0
	var axis := Vector3.ZERO
	if _input.steering_mode == CarInput.SteeringMode.SCREEN_RELATIVE:
		var dir := Vector3(_input.move_world.x, 0.0, _input.move_world.z)
		if dir.length() > 0.2:
			axis = Vector3.UP.cross(dir.normalized())   # tilts the car's up vector toward the pressed direction
	else:
		# W = nose down, S = nose up, A = roll left, D = roll right.
		axis = xf.basis.x * -_input.throttle + (-xf.basis.z) * -_input.steer
	state.apply_torque(axis * tuning.air_control_accel * inertia_avg)
	state.apply_torque(xf.basis.y.cross(Vector3.UP) * tuning.air_auto_level * inertia_avg)  # gentle self-levelling
	state.apply_torque(-state.angular_velocity * tuning.air_angular_damp * inertia_avg)

func _update_landing(state: PhysicsDirectBodyState3D, xf: Transform3D, fwd: Vector3, dt: float) -> void:
	if grounded_count == 0:
		air_time += dt
		_was_airborne = true
		return
	if _was_airborne:
		_was_airborne = false
		if air_time >= tuning.min_air_time_for_landing:
			_landing_window = tuning.landing_window
		air_time = 0.0
	if _landing_window > 0.0:
		_landing_window -= dt
		if grounded_count == WHEELS and xf.basis.y.dot(_ground_normal) >= tuning.perfect_landing_dot:
			_landing_window = 0.0
			var fwd_g := (fwd - _ground_normal * fwd.dot(_ground_normal)).normalized()
			state.apply_central_impulse(fwd_g * tuning.landing_boost * mass)
			_pending_landing_reward = true   # battery + signal handled in _physics_process
```

#### 7.3.5 Game logic (`car.gd`, main-thread side)

```gdscript
func _physics_process(delta: float) -> void:
	if not Net.is_authority():
		return
	_input = input_provider.get_car_input(self) if input_provider != null else CarInput.new()
	if frozen:
		_input = CarInput.neutral(_input.aim_point)
	last_aim_point = _input.aim_point
	for id: int in _bump_cooldowns.keys():
		_bump_cooldowns[id] = maxf(0.0, _bump_cooldowns[id] - delta)
	_update_battery(delta)
	_flush_events()
	if _input.fire and held_item != null:
		var item := held_item
		set_held_item(null)
		item_used.emit(self, item, _input.aim_point)   # Match spawns the effect
	_update_recovery(delta)

func _update_battery(delta: float) -> void:
	is_drifting = grounded_count >= 2 and absf(forward_speed) > tuning.drift_min_speed \
		and absf(lateral_speed) > tuning.drift_slip_threshold
	var gain := 0.0
	if is_drifting:
		gain += tuning.drift_charge_rate
	if grounded_count == 0 and air_time > tuning.air_charge_delay:
		gain += tuning.air_charge_rate
	if pad_overlaps > 0 and linear_velocity.length() < tuning.pad_max_speed:
		gain += tuning.pad_charge_rate
	is_boosting = _input.boost and battery > 0.0
	if is_boosting:
		gain -= tuning.boost_drain_rate
	set_battery(battery + gain * delta)

func _flush_events() -> void:
	if _pending_landing_reward:
		_pending_landing_reward = false
		set_battery(battery + tuning.perfect_landing_battery)
		perfect_landing.emit(self)
	for b in _pending_bumps:
		bumped.emit(self, b.attacker, b.strength)
	_pending_bumps.clear()

func _update_recovery(delta: float) -> void:
	_reset_cooldown = maxf(0.0, _reset_cooldown - delta)
	if global_basis.y.dot(Vector3.UP) < tuning.flip_dot and linear_velocity.length() < 3.0:
		_upside_down_time += delta
	else:
		_upside_down_time = 0.0
	if (_input.reset and _reset_cooldown <= 0.0) or _upside_down_time > tuning.flip_auto_time:
		_upside_down_time = 0.0
		_reset_cooldown = tuning.reset_cooldown
		var f := -global_basis.z
		f.y = 0.0
		if f.length_squared() < 0.01:
			f = Vector3.FORWARD
		teleport_to(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3.UP * tuning.reset_lift))
	if global_position.y < tuning.kill_y:
		respawn_requested.emit(self)

## Teleports must go through _integrate_forces; setting global_position on a RigidBody3D fights the solver.
func teleport_to(xf: Transform3D) -> void:
	_pending_teleport = xf

func apply_knockback(velocity_change: Vector3, spin: float) -> void:
	apply_central_impulse(velocity_change * mass)
	apply_torque_impulse(Vector3.UP * spin * tuning.inertia.y)

func set_battery(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if not is_equal_approx(nv, battery):
		battery = nv
		battery_changed.emit(battery)

func set_held_item(item: ItemDef) -> void:
	held_item = item
	item_changed.emit(item)
```

Charging pads increment and decrement `pad_overlaps` in their `body_entered` / `body_exited` handlers.

#### 7.3.6 Bumping

Each car handles its own side of a collision: it computes how hard the other car drove into it and applies knockback to itself. Symmetric and simple. A parked car hit at full speed flies; the attacker only feels the physics engine's normal response.

```gdscript
func _detect_bumps(state: PhysicsDirectBodyState3D) -> void:
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as Car
		if other == null or other == self:
			continue
		var id := other.get_instance_id()
		if _bump_cooldowns.get(id, 0.0) > 0.0:
			continue
		var dir := state.transform.origin - other.global_position
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var attack := other.linear_velocity.dot(dir)   # how fast the other car drove INTO me
		if attack < tuning.bump_min_speed:
			continue
		var strength := tuning.bump_base + attack * tuning.bump_speed_scale
		if other.is_boosting:
			strength *= tuning.bump_boost_mult
		state.apply_central_impulse((dir * strength + Vector3.UP * tuning.bump_pop) * mass)
		state.apply_torque_impulse(Vector3.UP * randf_range(-1.0, 1.0) * tuning.bump_spin * tuning.inertia.y)
		_bump_cooldowns[id] = tuning.bump_cooldown
		_pending_bumps.append({"attacker": other, "strength": strength})
```
(`randf_range` here is cosmetic spin; acceptable on the authority.)

Match connects `bumped` and awards a hit when `strength >= tuning.bump_score_strength` (§7.6.5). It also triggers `play_effect(&"bump", …)` and camera shake if the local car is involved.

#### 7.3.7 Visuals (`car_visual.gd`, all in `_process`)

**Kenney model hookup** (`setup(model_scene: PackedScene, tuning: CarTuning, color: Color, is_local: bool)`):
1. Instance the GLB scene as child `Model`.
2. Compute the combined AABB of all `MeshInstance3D` descendants (in Visual space).
3. Rotate by `@export var model_yaw_deg := 180.0`. glTF models usually face +Z while our forward is −Z; the developer confirms in M1 and flips this value if the car drives backwards visually.
4. Uniform scale so the AABB length equals `@export var visual_length := 2.0`.
5. Offset so the AABB is centered in X/Z and its bottom sits at `ground_y_at_rest`:
   `sag = (tuning.mass * g * tuning.gravity_scale / 4) / tuning.spring_strength` with `g = ProjectSettings.get_setting("physics/3d/default_gravity")`;
   `ground_y_at_rest = mount_y − (rest_length − sag) − wheel_radius` (≈ −0.6 with defaults).
6. **Wheels:** find descendants whose name contains "wheel" (case-insensitive). If exactly four are found, classify them by position in car space (front: z < 0, left: x < 0). Reparent each into its own pivot `Node3D` under Visual, keeping its global transform. Store base positions (they correspond to the resting sag). Every frame:
   - `pivot.position.y = base.y + ((rest_length − sag) − car.wheel_spring_len[i])` (compressed = higher; airborne = drops)
   - spin: `wheel.rotate_object_local(Vector3.RIGHT, -car.forward_speed / visual_wheel_radius * delta)` (flip the sign if it spins backwards)
   - front pivots: `rotation.y = lerp_angle(rotation.y, car.last_steer * 0.5, 1.0 - exp(-12.0 * delta))`
   If not exactly four wheels are found, skip wheel animation and print one warning with the node names found.
7. Put all car meshes on render layer `RENDER_CARS` (`layers = 2`).
8. **Model choice:** `MatchConfig.car_model_path`, else the first existing of `race.glb`, `race-future.glb`, `sedan-sports.glb`, else the first `.glb` in the folder (list with `DirAccess`). Bots cycle through up to 5 different models so cars are easy to tell apart. Kenney models use a shared color atlas, so **player color goes on the turret, ring and label, not the car body.**

**Other visual parts (built in code):**
| Part | Spec |
|---|---|
| Turret | at the model's AABB top center: base `CylinderMesh` r 0.22 h 0.15, barrel `BoxMesh` 0.12 × 0.12 × 0.6 offset −Z 0.3, player color. `Marker3D` "Muzzle" at the barrel tip. Yaw toward `car.last_aim_point` in car-local space: `var d := to_local(aim)`, `target = atan2(-d.x, -d.z)`, `turret.rotation.y = lerp_angle(turret.rotation.y, target, 1.0 - exp(-12.0 * delta))`. |
| Ring | flat ring under the car (`TorusMesh` inner 1.25 outer 1.45, scale y 0.05), unshaded, player color. Local player: brighter, slowly pulsing. |
| Name label | `Label3D`, billboard, `fixed_size`, `no_depth_test`, outline, 1.6 m above the car, player color. |
| Blob shadow | `Decal` pointing down, size ≈ 1.6 × 12 × 2.4, positioned so it reaches 10 m below the car, radial `GradientTexture2D` black → transparent, `cull_mask = RENDER_WORLD` only. Makes height readable when airborne. |
| Drift smoke | `GPUParticles3D` at each rear wheel, emitting while `is_drifting`. |
| Boost flame | `GPUParticles3D` at the rear center, emitting while `is_boosting`. |

### 7.4 Camera rig

```gdscript
class_name CameraRig
extends Node3D
## Fixed-angle top-down camera that lazily follows the local car with look-ahead toward velocity and cursor.

@export var pitch_deg: float = 56.0
@export var yaw_deg: float = 0.0              # FIXED for the whole match; screen-relative controls depend on it
@export var distance: float = 34.0
@export var fov_deg: float = 35.0             # narrow FOV from far away ≈ near-orthographic readability
@export var follow_sharpness: float = 3.5     # 1/s; lower = lazier
@export var height_sharpness: float = 1.5     # vertical follow is slower so bumps don't bob the view
@export var velocity_lookahead_time: float = 0.25
@export var max_velocity_lookahead: float = 5.0
@export var aim_lookahead_fraction: float = 0.25
@export var max_aim_lookahead: float = 6.0
@export var lookahead_sharpness: float = 2.5
@export var shake_decay: float = 1.6
@export var shake_max_offset: float = 0.6

var target: Car = null
var aim_point: Vector3 = Vector3.ZERO   # written by PlayerInput
var has_aim: bool = false

@onready var camera: Camera3D = $Camera3D
var _focus: Vector3 = Vector3.ZERO
var _lookahead: Vector3 = Vector3.ZERO
var _trauma: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0

func _ready() -> void:
	# Moved in _process from interpolated targets → own interpolation off.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = fov_deg
	camera.current = true
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	var pitch := deg_to_rad(pitch_deg)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)

func screen_up_world() -> Vector3:
	var v := -global_basis.z
	v.y = 0.0
	return v.normalized()

func screen_right_world() -> Vector3:
	var v := global_basis.x
	v.y = 0.0
	return v.normalized()

func snap_to_target() -> void:
	if target != null:
		_focus = target.global_position
		_lookahead = Vector3.ZERO
		global_position = _focus

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var car_pos := target.get_global_transform_interpolated().origin
	var vel := target.linear_velocity
	vel.y = 0.0
	var wanted := (vel * velocity_lookahead_time).limit_length(max_velocity_lookahead)
	if has_aim:
		var to_aim := aim_point - car_pos
		to_aim.y = 0.0
		wanted += (to_aim * aim_lookahead_fraction).limit_length(max_aim_lookahead)
	_lookahead = _lookahead.lerp(wanted, 1.0 - exp(-lookahead_sharpness * delta))
	var goal := car_pos + _lookahead
	var xz := Vector2(_focus.x, _focus.z).lerp(Vector2(goal.x, goal.z), 1.0 - exp(-follow_sharpness * delta))
	var y := lerpf(_focus.y, goal.y, 1.0 - exp(-height_sharpness * delta))
	_focus = Vector3(xz.x, y, xz.y)
	global_position = _focus

	_time += delta
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	var s := _trauma * _trauma * shake_max_offset
	camera.h_offset = _noise.get_noise_2d(_time * 60.0, 0.0) * s
	camera.v_offset = _noise.get_noise_2d(0.0, _time * 60.0) * s
```

### 7.5 Player input and mouse aim

```gdscript
class_name PlayerInput
extends Node
## The ONLY gameplay code that reads Input or the mouse.

var car: Car
var camera_rig: CameraRig
var steering_mode: CarInput.SteeringMode = CarInput.SteeringMode.SCREEN_RELATIVE
var enabled: bool = true

var aim_point: Vector3 = Vector3.ZERO
var aim_normal: Vector3 = Vector3.UP
var _fire_latched: bool = false
var _reset_latched: bool = false
var _current: CarInput = CarInput.new()

func _ready() -> void:
	process_physics_priority = -10   # run before Car._physics_process

func _physics_process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_update_aim()
	var i := CarInput.new()
	i.steering_mode = steering_mode
	i.aim_point = aim_point
	if enabled:
		if Input.is_action_just_pressed("fire"):
			_fire_latched = true
		if Input.is_action_just_pressed("reset"):
			_reset_latched = true
		var x := Input.get_axis("move_left", "move_right")
		var y := Input.get_axis("move_down", "move_up")
		i.move_world = (camera_rig.screen_right_world() * x + camera_rig.screen_up_world() * y).limit_length(1.0)
		i.throttle = y
		i.steer = -x   # + = left
		i.handbrake = Input.is_action_pressed("handbrake")
		i.boost = Input.is_action_pressed("boost")
	_current = i
	camera_rig.aim_point = aim_point
	camera_rig.has_aim = true

## Called by the car once per tick; edge-triggered actions are consumed here.
func get_car_input(_car: Car) -> CarInput:
	_current.fire = _fire_latched
	_current.reset = _reset_latched
	_fire_latched = false
	_reset_latched = false
	return _current

func _update_aim() -> void:
	var cam := camera_rig.camera
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, Layers.WORLD | Layers.CARS, [car.get_rid()])
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit.position
		aim_normal = hit.normal
	else:
		var p: Variant = Plane(Vector3.UP, car.global_position.y).intersects_ray(from, dir)
		if p != null:
			aim_point = p
			aim_normal = Vector3.UP
```

**Ballistics helper (`core/ballistics.gd`):**
```gdscript
class_name Ballistics

static func lob_flight_time(distance: float, max_range: float) -> float:
	return lerpf(0.45, 1.0, clampf(distance / max_range, 0.0, 1.0))

## Launch velocity so a projectile under `gravity` travels from `from` to `to` in `t` seconds.
static func lob_velocity(from: Vector3, to: Vector3, gravity: float, t: float) -> Vector3:
	return (to - from) / t + Vector3.UP * (0.5 * gravity * t)

## Clamps the horizontal distance; if clamped, finds the surface height under the new point with a down-ray.
static func clamp_target(space: PhysicsDirectSpaceState3D, origin: Vector3, target: Vector3, max_range: float) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if flat.length() <= max_range:
		return target
	var p := origin + flat.normalized() * max_range
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 40.0, Layers.WORLD)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3(p.x, origin.y, p.z)
```
(Down-rays need physics access: call `clamp_target` from `_physics_process` only; the preview caches the result.)

**AimVisuals (local player only, `_process`):**
- **Reticle:** flat ring mesh at `aim_point + aim_normal * 0.05`, oriented to `aim_normal`, unshaded. Color by held item: white (none), orange (rocket), blue (balloon).
- **Rocket:** faint straight line from the muzzle toward the aim point (max 8 m).
- **Balloon:** dotted arc (24 samples of the lob parabola, `ImmediateMesh` line strip) from the muzzle to the clamped target, plus a landing ring of the explosion radius at the clamped target.
- 2D crosshair `TextureRect` follows the mouse (`mouse_filter = IGNORE`).

### 7.6 Items and pickups

#### 7.6.1 ItemDef and registry

```gdscript
class_name ItemDef
extends Resource
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
```

`ItemRegistry.all() -> Array[ItemDef]` builds the definitions in code (move to `.tres` later):

| id | kind | aim | details | weight_leader | weight_last |
|---|---|---|---|---|---|
| `battery_pack` | BATTERY | NONE | +50 % battery | 35 | 5 |
| `bottle_rocket` | ROCKET | STRAIGHT | 1 rocket | 40 | 25 |
| `water_balloon` | BALLOON | LOB | range 22 m | 25 | 30 |
| `rocket_trio` | ROCKET | STRAIGHT | 3 rockets, 24° fan | 0 | 40 |

#### 7.6.2 Catch-up roll (Match)

```gdscript
## 0 = leading, 1 = last, 0.5 = everyone tied or alone.
func rank_fraction(car: Car) -> float:
	var mine: int = scores.get(car.player_id, 0)
	var better := 0
	var worse := 0
	for c in cars:
		var s: int = scores.get(c.player_id, 0)
		if s > mine:
			better += 1
		elif s < mine:
			worse += 1
	if better + worse == 0:
		return 0.5
	return float(better) / float(better + worse)

func roll_item(car: Car) -> ItemDef:
	var r := rank_fraction(car)
	var weights: Array[float] = []
	var total := 0.0
	for def in item_defs:
		var w := maxf(0.0, lerpf(def.weight_leader, def.weight_last, r))
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	for i in item_defs.size():
		pick -= weights[i]
		if pick <= 0.0:
			return item_defs[i]
	return item_defs.back()
```
In each mode, "rank" means that mode's score. POC mode **Bump Brawl**: score = hits landed.

#### 7.6.3 ItemBox (`item_box.gd`, `Area3D`)

- `collision_layer = PICKUPS`, `collision_mask = CARS`; shape: box 1.4; visual: 1 m cube, rotating and bobbing, semi-transparent rainbow material, "?" `Label3D`.
- On `body_entered` (authority only): if `active`, the body is a `Car`, and `car.held_item == null` → `car.set_held_item(match.roll_item(car))`, deactivate.
- Deactivate: hide, `set_deferred("monitoring", false)`, start a child `Timer` (`respawn_time = 6.0`). Never use `get_tree().create_timer` here, because it can outlive the match.
- Reactivate: show, `set_deferred("monitoring", true)`, then one frame later check `get_overlapping_bodies()` for a car already parked inside.
- `play_effect(&"pickup", …)` on pickup.

#### 7.6.4 Firing (Match listens to `Car.item_used`)

```gdscript
func _on_item_used(car: Car, item: ItemDef, aim_point: Vector3) -> void:
	if not Net.is_authority():
		return
	match item.kind:
		ItemDef.Kind.BATTERY:
			car.set_battery(car.battery + item.battery_amount)
		ItemDef.Kind.ROCKET:
			for n in item.count:
				var t := 0.0 if item.count == 1 else float(n) / float(item.count - 1) - 0.5
				spawn_projectile(car, item, aim_point, t * item.spread_deg)
		ItemDef.Kind.BALLOON:
			var space := car.get_world_3d().direct_space_state
			spawn_projectile(car, item, Ballistics.clamp_target(space, car.global_position, aim_point, item.max_range), 0.0)
	play_effect(&"fire", car.get_muzzle_position(), 0.0)
```
`Car.get_muzzle_position()` returns the turret muzzle marker's global position (fallback: car position + 0.8 m up).

#### 7.6.5 Projectiles (`projectile.gd`, `Node3D`, manual sweep — deterministic, network-friendly)

| Param | Rocket | Balloon |
|---|---|---|
| speed / launch | 35 m/s toward the aim point, pitch clamped to ±25°, rotated by spread around +Y | `Ballistics.lob_velocity(muzzle, target, 25.0, flight_time)` |
| gravity | 0 | 25 m/s² |
| lifetime | 3 s | 3 s |
| explosion radius | 3.5 m | 4.5 m |
| knockback strength (horizontal, at center) | 11 m/s | 8 m/s |
| up strength | 4 m/s | 3 m/s |
| visual | small cylinder + flame particles, faces velocity | blue sphere, slight wobble |

Each physics tick (authority only):
1. `velocity.y -= gravity * delta`; `to = from + velocity * delta`.
2. Ray from `from` to `to` against `WORLD | CARS`; exclude the owner during `owner_immunity` (0.25 s).
3. Generous car hit test: for each car, `Geometry3D.get_closest_point_to_segment(car.global_position, from, to)`; if closer than `hit_radius` (0.9 m) → hit. This keeps it casual-friendly.
4. On any hit or when lifetime runs out → `match.explode(position, radius, strength, up_strength, owner_car)`, `queue_free()`.
5. Otherwise move, and face the velocity (skip `look_at` when velocity is almost vertical).

```gdscript
func explode(pos: Vector3, radius: float, strength: float, up_strength: float, attacker: Car) -> void:
	for car in cars:
		var offset := car.global_position - pos
		var dist := offset.length()
		if dist > radius:
			continue
		var falloff := 1.0 - dist / radius
		var dir := Vector3(offset.x, 0.0, offset.z)
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		car.apply_knockback((dir * strength + Vector3.UP * up_strength) * falloff, rng.randf_range(-3.0, 3.0) * falloff)
		if car != attacker and strength * falloff >= car.tuning.bump_score_strength * 0.6:
			register_hit(attacker, car)
	play_effect(&"explosion", pos, radius)
```

**Scoring:** `register_hit(attacker, victim)` adds +1 to the attacker, at most once per second per attacker/victim pair (dictionary of timestamps), then emits `scores_changed`.

### 7.7 Bots (`bot_input.gd`)

Same `get_car_input` interface as `PlayerInput`, `process_physics_priority = -10`, always `SCREEN_RELATIVE`.
- **Think every 0.4 s** (random offset per bot): if no item → nearest active ItemBox; otherwise → nearest other car; fallback → random arena point.
- `move_world` = flat direction to the target.
- **Boost** when `battery > 0.5`, target farther than 15 m, and the angle to the target is under 20°.
- **Fire** when holding an item and the target car is in range (rocket 25 m, balloon `max_range`), after a reaction delay of 0.3–0.8 s. `aim_point = target position + target velocity × lead time` (0.3 s for rockets, flight time for balloons) plus random error of ±1.5 m.
- Exported `aim_error` and `reaction_delay` for difficulty.
- Bots respect `frozen` automatically, because the car replaces their input with neutral input.

### 7.8 HUD and debug tools

**HUD** (`bind(local_car, match)`): battery bar (bottom center, flashes when full), item slot (bottom right, name plus color), scoreboard (top right, rank / name / score, local player highlighted), round timer (top center), countdown (center), popups ("PERFECT LANDING!", "+1", fading), steering mode label (small, bottom left).

**Debug overlay (F3):** FPS, physics ticks, forward/lateral speed, grounded wheel count, drifting, boosting, air time, battery, held item, score / rank / `rank_fraction`, current item roll probabilities for the local car (computed from the weights), steering mode, orphan node count.

**Debug draw (F4):** `ImmediateMesh` cleared every frame: wheel rays (green grounded, red airborne), suspension force per wheel as a vertical line, velocity vector, aim line.

**Debug keys (only if `OS.is_debug_build()`):** F2 toggle steering, F6 fill battery, F7 +1 score to the local player, 1–4 give item by registry index.

**Effects (`Match.play_effect(kind, pos, param)`):** `explosion` (expanding unshaded sphere that fades + particle burst), `bump` (sparks), `pickup` (poof), `fire` (muzzle flash), `landing` (ring). If the local car is near or involved, add camera trauma (bump: `strength / 30`, explosion: by distance).

---

## 8. Tuning reference (`car_tuning.gd`)

Every feel number lives here. While the game runs, select a car in the *Remote* scene tree and edit `tuning` live.

```gdscript
class_name CarTuning
extends Resource

@export_group("Body")
@export var mass: float = 150.0
@export var inertia: Vector3 = Vector3(60.0, 65.0, 40.0)   # x pitch, y yaw, z roll; high roll value = harder to flip
@export var center_of_mass: Vector3 = Vector3(0.0, -0.35, 0.0)
@export var gravity_scale: float = 2.0                      # arcade: heavier, snappier jumps
@export var max_angular_speed: float = 12.0

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
@export var reverse_max_speed: float = 7.0
@export var reverse_accel: float = 10.0
@export var brake_decel: float = 28.0
@export var rolling_decel: float = 3.0
@export var hold_brake_speed: float = 1.5
@export var hold_brake_max_accel: float = 14.0
@export var handbrake_decel: float = 6.0
@export var downforce_per_speed: float = 0.4

@export_group("Grip and steering")
@export var front_grip: float = 0.85          # fraction of sideways velocity removed per tick
@export var rear_grip: float = 0.8
@export var drift_front_grip: float = 0.6
@export var drift_rear_grip: float = 0.12
@export var max_lateral_accel: float = 45.0   # caps grip per wheel → natural slide at speed
@export var grip_force_height: float = -0.2   # car-local y where grip is applied; lower = less body roll
@export var max_yaw_rate: float = 3.2         # rad/s at full steer
@export var yaw_response: float = 10.0
@export var full_steer_speed: float = 5.0
@export var min_steer_factor: float = 0.35
@export var high_speed_steer_mult: float = 0.75
@export var drift_yaw_mult: float = 1.4
@export var drift_min_speed: float = 6.0
@export var drift_slip_threshold: float = 3.0

@export_group("Screen-relative assist")
@export var screen_deadzone: float = 0.2
@export var screen_full_steer_angle_deg: float = 50.0
@export var uturn_angle_deg: float = 110.0
@export var uturn_min_speed: float = 6.0
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
@export var air_auto_level: float = 3.0
@export var air_angular_damp: float = 1.5
@export var min_air_time_for_landing: float = 0.35
@export var landing_window: float = 0.15
@export var perfect_landing_dot: float = 0.92
@export var landing_boost: float = 7.0
@export var perfect_landing_battery: float = 0.1

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
@export var flip_auto_time: float = 1.2
@export var reset_lift: float = 1.5
@export var reset_cooldown: float = 2.0
@export var kill_y: float = -15.0
```

**Tuning tips for the developer**
- Car feels floaty → raise `gravity_scale` or `downforce_per_speed`.
- Car flips in turns → lower `grip_force_height`, raise `inertia.z`, lower `center_of_mass.y`.
- Suspension jitters at rest → raise `spring_damping` or set physics ticks to 120.
- Turning feels sluggish → raise `max_yaw_rate` and `yaw_response`.
- Drift spins out → raise `drift_rear_grip` or lower `drift_yaw_mult`.
- Bumps too weak or too wild → `bump_base`, `bump_speed_scale`, `bump_pop`.

---

## 9. Milestones and acceptance tests

After every milestone the agent runs the checks from `CLAUDE.md` (import + headless smoke test) and hands this checklist to the developer.

### M0 — Project skeleton
Folders, autoloads, project settings (§3), layer names, `Layers`, `InputSetup`, `main.tscn` with a placeholder main menu (Play does nothing yet, Quit works), `--autostart` parsing stubbed.
- [ ] Import is clean, the game starts into the menu, Quit closes the app.

### M1 — Arena, car physics, camera (classic steering only)
Arena builder and test arena (§7.2), checker floor, light and environment; car scene, `CarTuning`, `CarInput`, physics core (§7.3.4), recovery and respawn; Kenney visual with wheels, blob shadow, label, ring; `PlayerInput` (keys only); `CameraRig`; debug overlay (F3) and debug draw (F4). Play starts a match directly (no countdown yet).
- [ ] Parked on flat ground: no jitter, no creeping (< 0.05 m/s after 1 s), body level, visible sag.
- [ ] Full throttle reaches ~18 m/s in about 2 s; releasing rolls to a stop; brake and reverse work.
- [ ] Climbs the 14° and 25° ramps from standstill; the 35° ramp slowly.
- [ ] Parked on the 14° and 25° slopes without input: doesn't roll (< 0.2 m/s).
- [ ] Humps at full speed: bounces without flipping; wheels follow the suspension.
- [ ] Kicker at full speed: clear jump, lands on its wheels.
- [ ] Drives off the table's north edge and lands.
- [ ] Driving across the side slope: no sideways sliding at low speed.
- [ ] Handbrake + steer at speed: rear slides out, drift is controllable.
- [ ] Camera: smooth, lazy follow; no jitter on 60 Hz and 144 Hz monitors; slight lead in driving direction.
- [ ] Model faces the driving direction (otherwise flip `model_yaw_deg`).
- [ ] R puts the car back on its wheels; falling below −15 respawns it.

### M2 — Screen-relative steering and toggle
Drive resolution (§7.3.3), F2 toggle, steering label in the HUD, setting persisted.
- [ ] Holding D always drives toward screen-right, whatever the car's heading.
- [ ] Opposite direction at speed → handbrake U-turn; at low speed → tight turn.
- [ ] Diagonals work.
- [ ] Nose against a wall: auto-reverse frees the car within ~1.5 s.
- [ ] Classic mode still works after toggling back.

### M3 — Game flow
Main menu (Play, bots 0–9, steering, Quit), `MatchConfig`, `Game.start_match / exit_to_menu / restart_match`, countdown, round timer, in-game menu (Escape), results screen, mouse modes, `--autostart` args.
- [ ] Five loops of start → Escape → Exit to menu → start, without errors.
- [ ] Orphan node count returns to its baseline after each exit.
- [ ] The in-game menu doesn't freeze the world; the car coasts and holds still.
- [ ] Results appear when the timer ends (test with `--round=20`); Play again and Exit to menu both work.
- [ ] Quit is only available in the main menu and closes the app.

### M4 — Mouse aim, pickups, items
Aim raycast, AimVisuals (reticle, rocket line, lob arc), turret, `ItemDef` + registry + catch-up roll, ItemBox (respawn, overlap re-check), HUD item slot, firing, projectiles, explosions with knockback, effects, debug give-item keys 1–4.
- [ ] Reticle sits on whatever is under the mouse, including the table top and ramps.
- [ ] Turret turns smoothly toward the reticle, also while driving and on slopes.
- [ ] Rocket flies straight toward the reticle; rocket trio fans out.
- [ ] Balloon lands at the reticle (within 0.5 m on flat ground) and clamps at max range; the landing ring shows where.
- [ ] A second item cannot be picked up while holding one; boxes respawn after 6 s.
- [ ] Explosions knock cars back, weaker toward the edge of the radius; battery pack fills the battery.

### M5 — Battery, boost, air control, landing
Battery gain sources, boost, battery bar, charging pads, air control (both modes) with self-levelling, perfect landing + popup, drift smoke and boost flame.
- [ ] Drifting visibly fills the bar (about 7 s from empty to full).
- [ ] The kicker jump gives some charge; parking on a pad fills it in about 3 s, but only while nearly stopped.
- [ ] Boost drains in about 2.5 s with a clear speed gain.
- [ ] WASD tilts the car in the air in both steering modes.
- [ ] A level landing after the kicker shows "PERFECT LANDING!" and gives a push and some battery.
- [ ] A car lying on its roof recovers by itself after about 1.2 s.

### M6 — Bots, bumping, scoring, catch-up
`BotInput`, bump detection and knockback (§7.3.6), hit registration with cooldown, scoreboard, rank fraction, item probabilities in the debug overlay, camera shake and bump effect.
- [ ] Ramming a parked bot at full speed launches it at least two car lengths with a small hop.
- [ ] Low-speed glancing contact does nothing special.
- [ ] A boosted ram is noticeably stronger.
- [ ] Hits are credited to the attacker, at most once per second per victim.
- [ ] With 9 bots the game holds 60 physics ticks without drops.
- [ ] Debug overlay: `rocket_trio` 0 % while leading, about 40 % while last (use F7 to change ranks).

### M7 (optional polish)
Tilt-shift depth of field (`CameraAttributesPractical`, near and far blur), skid marks, occlusion cutout and x-ray silhouettes (§10.1).

---

## 10. Later phases (architecture notes)

### 10.1 Occlusion cutout (M7)

Cut a dithered hole into everything between the camera and the local car, instead of fading whole objects. No transparency sorting issues; works on huge objects.

- Add global shader parameters `focus_car_pos` (vec3) and `cutout_radius` (float) in *Project Settings → Globals → Shader Globals*. CameraRig sets `RenderingServer.global_shader_parameter_set("focus_car_pos", car_pos)` every frame.
- Arena materials use a shared shader that discards fragments that are closer to the camera than the car and within `cutout_radius` of the camera-to-car line, with a 4 × 4 Bayer dither over the outer 30 % of the radius:

```glsl
shader_type spatial;
uniform vec3 albedo : source_color = vec3(1.0);
global uniform vec3 focus_car_pos;
global uniform float cutout_radius;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[y * 4 + x] + 0.5) / 16.0;
}

void fragment() {
	vec3 world_frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_car = focus_car_pos - cam;
	float t = dot(world_frag - cam, to_car) / dot(to_car, to_car);   // 0 = camera, 1 = car
	float d = distance(world_frag, cam + to_car * clamp(t, 0.0, 1.0));
	if (t < 0.97 && d < cutout_radius) {
		float keep = smoothstep(cutout_radius * 0.7, cutout_radius, d);
		if (keep < bayer4(FRAGCOORD.xy)) discard;
	}
	ALBEDO = albedo;
}
```
- **X-ray silhouettes** for other cars hidden behind objects: a `next_pass` material on car meshes, rendered after opaque geometry, that reads the depth texture (`hint_depth_texture`) and only draws a flat player-colored silhouette where the car fragment is behind the scene depth.

### 10.2 LAN multiplayer (after the POC)
- `Net.host_lan(port)` / `Net.join_lan(address, port)` with `ENetMultiplayerPeer`; nothing else in gameplay changes transport.
- LAN discovery: the host broadcasts a UDP beacon every second (`PacketPeerUDP`, broadcast enabled) with lobby name, player count and port; clients list what they hear.
- Clients run `PlayerInput` locally and send `CarInput.to_dict()` to the server every tick (unreliable RPC); the server feeds it into a `NetworkInput` provider that implements `get_car_input`.
- Server simulates; car transforms and velocities sync via `MultiplayerSynchronizer` at 20–30 Hz, interpolated on clients. Discrete events (pickups, explosions, scores, effects) are reliable RPCs through the existing choke points.
- Internet play later: the same design accepts netfox rollback/prediction, and netfox.noray for NAT punchthrough and relay.

---

## 11. Pitfalls checklist

- **Godot 3 syntax** creeping in (see `CLAUDE.md`).
- `apply_force(force, position)`: `position` is an offset from the body origin in **global orientation**, not a world position.
- Teleport a RigidBody3D via `state.transform` in `_integrate_forces` (`_pending_teleport`), then `reset_physics_interpolation()`.
- Physics queries only inside `_physics_process` or `_integrate_forces`.
- Don't add or remove physics nodes inside `_integrate_forces` or Area3D signal callbacks; use `call_deferred` / `set_deferred`.
- Input producers need `process_physics_priority = -10` so the car reads fresh input.
- With physics interpolation on: the camera follows `get_global_transform_interpolated()` and has its own interpolation off.
- The blob shadow decal draws on cars too unless its `cull_mask` excludes the cars render layer.
- Timers that can outlive a match must be child `Timer` nodes, not `SceneTreeTimer`s.
- Everything that should be aimable needs collision on the world or cars layer.
- Physical keycodes for WASD (QWERTZ layouts).
- Don't commit `.godot/`; do commit `*.uid` files; never write `uid=` attributes into `.tscn` files by hand.
