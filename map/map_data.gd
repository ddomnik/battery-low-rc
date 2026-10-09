class_name MapData
extends RefCounted
## A validated map, ready to build (see MapLoader for the file format, Arena for the building).
## Everything here is plain data: types, numbers, colors, model ids. Nothing in a map can run code.

var id: String = ""
var name: String = ""
var author: String = ""

# Ground and outline.
var floor_size: Vector2 = Vector2(90.0, 90.0)   # x × z, centered on the origin, top at y = 0
var floor_material: String = "checker"          # "checker", "color" or "none" (no floor: a terrain model is the ground)
var floor_color: Color = Color(0.75, 0.72, 0.66)

# Light.
var sun_rotation_deg: Vector3 = Vector3(-55.0, 35.0, 0.0)
var ambient_energy: float = 0.6

## Placed objects, validated: {"type": &"box"|&"wedge"|&"cylinder"|&"prop"|&"path", "transform": Transform3D,
## "border": bool (outer wall: left out in modes without walls), ...}
## box / wedge / cylinder: "size": Vector3, "color": Color.   prop: "model": String ("nature/…" catalog or
## "map/<name>" own model), "scale": Vector3, "collision": "convex"|"mesh"|"box"|"none".   path: "points": PackedVector3Array, "profile": "road"|"wall",
## "width": float, "height": float, "color": Color.   fluid: "preset", "size" (x, depth, z), "color", "opacity",
## "texture" ("map/<name>" or ""), "damage", "slow", "drag", "buoyancy", "grip", "kill", "current" (Vector2), "coat".
var objects: Array[Dictionary] = []

var spawns: Array[Transform3D] = []   # car start spots (y = surface), facing −Z of the basis
var items: Array[Vector3] = []        # item box centers
var pads: Array[Vector3] = []         # charging pad centers (on the surface)
var podium: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 13.0))
