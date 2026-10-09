# Making maps for Battery Low!

You build a map as a normal scene in the Godot editor, click **Export map**, and play it. The game never
loads your scene directly: the export writes a plain data file (`map.json`) that the game reads, so maps are safe to
share later (they cannot contain code).

Every map lives in its own folder:

```
maps/<map_id>/
  source.tscn   ← the scene you edit (keep it)
  map.json      ← what the game plays (written by Export map)
  models/       ← your own .glb models (terrain etc. from Blender), optional
```

`<map_id>` must be lowercase letters, digits, `_` or `-` (e.g. `forest_run`).

Godot basics you will use: fly around the 3D view with the **right mouse button held + W A S D** (hold Shift to
go faster), select with left click, then **W** move, **E** rotate, **R** scale with the gizmo
([Godot: Introduction to 3D](https://docs.godotengine.org/en/stable/tutorials/3d/introduction_to_3d.html)).

---

## 1. Create and save a map

**Quickest: start from an existing map.**
1. In the FileSystem dock, right-click `maps/meadow` → **Duplicate…** → name it e.g. `my_map`.
2. Open `maps/my_map/source.tscn`.
3. Select the root node (**MapSource**) and change **Map Name** in the Inspector.
4. Save (Ctrl+S). The scene always exports into the folder it is saved in, so the copy never overwrites Meadow.

**From scratch.**
1. In the FileSystem dock: right-click `maps` → **New Folder…** → `my_map`.
2. **Scene → New Scene → Other Node** → search **MapSource** → Create.
3. **Scene → Save Scene As…** → `maps/my_map/source.tscn`.

**Map settings** (select the MapSource root, Inspector):
- **Map Name**, **Author** – shown in the main menu.
- **Floor Size** – the flat ground in meters (x × z), centered on the origin.
  **Floor Material**: Checker, Color, or **None** (no flat floor – use this when your Blender terrain is the ground).
- **Light** – sun direction and ambient light.
- **Map Id** – leave empty (uses the folder name).

Directions: north is **−Z** (away from the camera's default view), screen-right is **+X**.

---

## 2. Add objects

Tip: keep things tidy with plain **Node3D** folders (the example maps have Shapes, Props, Paths, Spawns, Items,
Pads). Anything inside folders is exported too. **Hidden nodes (eye icon off) are not exported** – handy for drafts.

To add a node: select the parent (root or a folder) → **Ctrl+A** (Add Child Node) → type the name.

### Trees, rocks and other models
1. In the FileSystem dock open `assets/kenney_nature_kit/`.
2. **Drag a `.glb` file into the 3D view** (or onto a folder node in the Scene tree).
3. Move / rotate / scale it. For a natural look: turn each one a different amount around Y, tilt it a few degrees,
   vary the size (trees look right at about scale 3–5, big rocks 2–3). Avoid grid snapping.
4. Collision is automatic: models are solid; flowers, grass, flat plants and mushrooms are drive-through.
   To change that, select the model → **Node** dock (next to the Inspector) → **Groups** → add
   `map_no_collision` (drive through) or `map_box_collision` (a simple box).

Models can come from `assets/kenney_nature_kit/` or from **this map's own `models/` folder** (see "Terrain and models
from Blender" below). Anything else is skipped on export with a warning.

Collision override groups: `map_no_collision`, `map_box_collision`, `map_convex_collision` (simplified hull),
`map_mesh_collision` (exact triangles).

### Blocks, ramps and cylinders – **MapShape**
- Add **MapShape**, then in the Inspector pick **Kind** (Box / Ramp / Cylinder), **Size** and **Color**.
- Rotate it freely (any angle, also tilted). Scaling with the gizmo works too (it multiplies the size).
- A **Ramp** sits on the middle of its base and **rises toward −Z** (its tall, vertical side is at −Z).

### Curved roads and walls – **MapPath**
1. Add **MapPath**. It starts as a short curved road.
2. With it selected, the toolbar above the 3D view shows the path tools: **Select Points** (drag points and their
   handles to bend the curve), **Add Point** (click to append), **Delete Point**.
3. Inspector: **Profile** Road or Wall, **Width**, **Height**, **Color**.
   - **Road**: the curve is the *top* of the road. Raise the middle points to build a hill or bridge cars drive over.
   - **Wall**: stands on the curve.
4. The preview is exactly what the game builds (the export samples the curve every ~2 m).

### Outer walls
Maps have no automatic walls – build your own border with MapShapes (long boxes), curved MapPath walls or Blender
models. Add every outer-wall node to the group **`map_border`** (Node dock → Groups): those are left out in the
"Last on table" mode, where cars should be pushed off the edge. Keep the wall on the camera side (+Z, south) low
(≈ 0.5 m) so it never hides cars. The example maps keep theirs in a "Walls" folder.

### Water, lava, mud, acid – **MapFluid**
1. Add **MapFluid**. The node sits in the **middle of the surface**; the box reaches **Size.y** (depth) down.
   Turn it only around the vertical (fluids stay level); scaling multiplies the size.
2. Pick a **Preset** (Water, Lava, Mud, Acid) and click **Apply preset values** – that loads its look and
   behaviour; then change anything you like.
3. A fluid has no floor of its own: cars drive on whatever is below (floor, terrain) or float / sink in it.
   Put it in a dip of your terrain (lakes), on the floor (shallow puddles) or between walls (pools).

| Setting | Meaning |
|---|---|
| Color, Opacity, Texture | Look. Texture: a PNG from this map's `textures/` folder (`maps/<id>/textures/`, max 4096 px), tiled every 4 m and moved by the current |
| Damage | per 100 ms of touching. Last on table: raises the damage %; Deathmatch: every 10 damage pops a balloon; other modes: drains battery. Whoever pushed the car in gets the hit |
| Slow | top speed × while touching (1 = no slowdown) |
| Drag | how quickly a car **in** the fluid loses speed |
| Buoyancy | 0 = sinks to the bottom, 1 = a car fully under floats, above 1 floats higher. Floating cars can paddle and steer slowly |
| Grip | tyre grip × while touching (mud and lava are slippery) |
| Kill | touching it counts as falling off the map (respawn or out, knockout for the attacker) – lava pits |
| Current | m/s along the fluid's own X / Z: pushes cars along like a river (parked cars drift with it) |
| Coat | seconds of wet / muddy tyre tracks after leaving |

Bots steer around fluids that hurt (damage or kill) and skip item boxes inside them.

### Game markers
| Node | What | How to place |
|---|---|---|
| **MapSpawn** | car start | on the ground; the blue arrow = driving direction. At least **2**, ideally **10** |
| **MapItem** | item box | on the ground; the box floats 0.8 m above the marker |
| **MapPad** | charging pad (5 × 5 m) | on flat ground |
| **MapPodium** | winners' podium after a round | one, on open flat ground with room on its +Z side |

Tip: with a node selected, **Page Down** ("Snap Object to Floor") drops it onto the surface below.

---

## Terrain and models from Blender

Anything you model in Blender can be part of a map: a sculpted landscape, tunnels, bridges, cliffs, big rock
formations, buildings. `maps/hills/` is an example (its terrain was generated in code, but it is a normal .glb).

**In Blender**
1. Work in meters (1 unit = 1 m) and keep the map around the origin. Blender's Z-up becomes Godot's Y-up
   automatically on export. North in the game (−Z in Godot) is **+Y** in Blender.
2. Terrain: add a Plane, scale it to the map size, subdivide it (e.g. Subdivide / Multires), then sculpt it
   (Sculpt Mode: Draw, Grab, Smooth brushes) or use the built-in **A.N.T. Landscape** add-on. Keep slopes under
   about 25–30° where cars should drive.
3. Color it with materials / image textures, or vertex colors ("Color Attributes"). Image textures max 4096 px.
4. Optional but recommended for big terrains: make a lighter copy for collision (duplicate, Decimate modifier to
   ~10–20 % and apply it) and name the object with the suffix **`-colonly`**, e.g. `terrain-colonly`. The game uses
   it only for collision and never draws it; your detailed mesh is only drawn.
5. Apply transforms (Ctrl+A → All Transforms).
6. **File → Export → glTF 2.0** → Format **glTF Binary (.glb)** → save it as
   `maps/<map_id>/models/<name>.glb` (name: letters, digits, `_`, `-`). Everything must be embedded – the .glb
   format does that by default.

Limits per model: 20 MB file, 300 000 triangles, textures up to 4096 px, up to 32 different own models per map.
Only meshes are used – lights, cameras and animations in the file are ignored.

**In Godot**
1. Drag `maps/<map_id>/models/<name>.glb` into your `source.tscn` and leave it at the origin (or place it).
2. Set the MapSource **Floor Material** to **None** if the terrain is the ground.
3. Put trees, markers, roads etc. on top as usual. Spawns, items and pads go on the terrain surface
   (**Page Down** snaps a selected node down onto it).
4. Your own models collide **exactly** (triangle mesh) by default; small models can use the
   `map_convex_collision` group instead (cheaper).
5. **Vertex colors?** Select the .glb in the FileSystem dock → Import dock → **Import Script** →
   `res://map/authoring/vertex_color_import.gd` → **Reimport**, so the editor shows the colors like the game does.
6. After changing the model in Blender, just export over the same file – Godot reimports it automatically.

Why .glb is safe to share: it only contains geometry, materials and images. The game reads it with Godot's plain
glTF reader (never as a Godot scene), refuses files that reference other files on disk, and checks the limits.

---

## 3. Export and play

- **Export**: select the **MapSource** root → click **Export map** at the top of the Inspector. The **Output**
  panel shows `Map 'my_map' exported: … objects, … spawns …` in green, warnings in orange, errors in red
  (e.g. fewer than 2 spawns → nothing is written).
- **Test right away**: with `source.tscn` open press **F6** (Run Current Scene). It exports, then starts a match
  with 5 bots on your map. Esc → menu.
- **Play normally**: the map is in the main menu under **Map** (it remembers your choice).
- Command line: `godot --path . -- --autostart --map=my_map`.

Keep `source.tscn` – it is the editable version. `map.json` is regenerated on every export.

---

## Limits (checked by the game)

Up to 4000 objects, 256 points per curve, 2–16 spawns, 64 item spots, 16 pads, coordinates within ±1000 m,
sizes 0.05–500 m, scales 0.05–50. Map files over 2 MB are refused. Unknown things are skipped with a warning.

## Notes

- Objects made from your own models don't get the see-through cut-out when they hide your car (the car's
  silhouette still shows through).
- A Terrain3D node in a map scene is ignored on export (we went with Blender terrain instead).
