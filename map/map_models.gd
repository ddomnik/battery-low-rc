class_name MapModels
## A map's own 3D models and textures. Textures: maps/<map id>/textures/<name>.png ("map/<name>", fluids),
## read with Image.load_png_from_buffer (≤ 8 MB, ≤ 4096 px).
## Models (made in Blender etc.): maps/<map id>/models/<name>.glb, referenced in a map as
## "map/<name>". They may come from other players later, so they are read as plain glTF data — never through
## Godot's resource loader, which could pull in scripts:
## - .glb only, with every buffer and image embedded (no references to other files on disk)
## - size, triangle and texture limits
## - only meshes survive: lights, cameras, animations and anything else in the file are dropped
## Mesh nodes whose name ends in "col" / "colonly" (after "-" or "_", e.g. "terrain-colonly") are collision-only:
## used for physics, never drawn.

const MODELS_DIR := "models"
const EXTENSION := "glb"
const MAX_FILE_BYTES := 20_000_000
const MAX_TRIANGLES := 300_000
const MAX_TEXTURE_SIZE := 4096
const MAX_NAME := 40
const GLB_MAGIC := 0x46546C67           # "glTF"
const GLB_JSON_CHUNK := 0x4E4F534A      # "JSON"
const COLLISION_SUFFIXES: Array[String] = ["-colonly", "_colonly", "-col", "_col"]
const TEXTURES_DIR := "textures"
const MAX_TEXTURE_BYTES := 8_000_000

## Model file names: letters, digits, "_" and "-" (no dots or slashes).
static func valid_name(name: String) -> bool:
	if name.is_empty() or name.length() > MAX_NAME:
		return false
	for c in name:
		if not (c >= "a" and c <= "z") and not (c >= "A" and c <= "Z") and not (c >= "0" and c <= "9") \
				and c != "_" and c != "-":
			return false
	return true

static func path(map_id: String, name: String) -> String:
	return "%s%s/%s/%s.%s" % [MapCatalog.BUILTIN_DIR, map_id, MODELS_DIR, name, EXTENSION]

static func exists(map_id: String, name: String) -> bool:
	if not MapCatalog.valid_id(map_id) or not valid_name(name):
		return false
	var p := path(map_id, name)
	return FileAccess.file_exists(p) or ResourceLoader.exists(p)

static func texture_path(map_id: String, name: String) -> String:
	return "%s%s/%s/%s.png" % [MapCatalog.BUILTIN_DIR, map_id, TEXTURES_DIR, name]

static func texture_exists(map_id: String, name: String) -> bool:
	if not MapCatalog.valid_id(map_id) or not valid_name(name):
		return false
	var p := texture_path(map_id, name)
	return FileAccess.file_exists(p) or ResourceLoader.exists(p)

## "map/<name>" if file is one of map_id's own textures, else "".
static func texture_id_for_path(map_id: String, file: String) -> String:
	var name := file.get_file().get_basename()
	return "map/" + name if valid_name(name) and file == texture_path(map_id, name) else ""

## The texture (PNG read as plain image data), or null with the reason in errors.
static func load_texture(map_id: String, name: String, errors: Array[String]) -> Texture2D:
	if not texture_exists(map_id, name):
		errors.append("texture '%s' not found" % name)
		return null
	var p := texture_path(map_id, name)
	if not FileAccess.file_exists(p):   # exported game: built-in maps ship it imported (trusted)
		return load(p) as Texture2D
	var bytes := FileAccess.get_file_as_bytes(p)
	var image := Image.new()
	if bytes.size() > MAX_TEXTURE_BYTES or image.load_png_from_buffer(bytes) != OK:
		errors.append("texture '%s' is not a PNG up to %.0f MB" % [name, MAX_TEXTURE_BYTES / 1_000_000.0])
		return null
	if image.get_width() > MAX_TEXTURE_SIZE or image.get_height() > MAX_TEXTURE_SIZE:
		errors.append("texture '%s' is larger than %d px" % [name, MAX_TEXTURE_SIZE])
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## "map/<name>" if file is one of map_id's own models, else "".
static func id_for_path(map_id: String, file: String) -> String:
	var name := file.get_file().get_basename()
	return "map/" + name if valid_name(name) and file == path(map_id, name) else ""

## True for a collision-only mesh node (see the class description).
static func is_collision_node(node_name: String) -> bool:
	var lower := node_name.to_lower()
	for suffix in COLLISION_SUFFIXES:
		if lower.ends_with(suffix):
			return true
	return false

## The model as a fresh node tree (meshes only), or null with the reason in errors.
static func load_model(map_id: String, name: String, errors: Array[String]) -> Node3D:
	if not MapCatalog.valid_id(map_id) or not valid_name(name):
		errors.append("bad model name '%s'" % name)
		return null
	var p := path(map_id, name)
	if FileAccess.file_exists(p):
		return _load_glb(FileAccess.get_file_as_bytes(p), name, errors)
	# Exported game: built-in maps ship their models imported (res:// is the game itself, so trusted).
	if p.begins_with("res://") and ResourceLoader.exists(p):
		var scene := load(p) as PackedScene
		var node := scene.instantiate() as Node3D if scene != null else null
		if node != null:
			apply_vertex_colors(node)
		return node
	errors.append("model '%s' not found" % name)
	return null

static func _load_glb(bytes: PackedByteArray, name: String, errors: Array[String]) -> Node3D:
	if bytes.size() > MAX_FILE_BYTES:
		errors.append("model '%s' is larger than %.0f MB" % [name, MAX_FILE_BYTES / 1_000_000.0])
		return null
	if not check_glb(bytes, errors):
		errors.append("model '%s' is not a self-contained .glb" % name)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, "", state) != OK:
		errors.append("model '%s' could not be read" % name)
		return null
	for image in state.get_images():
		if image != null and (image.get_width() > MAX_TEXTURE_SIZE or image.get_height() > MAX_TEXTURE_SIZE):
			errors.append("model '%s': textures may be at most %d px" % [name, MAX_TEXTURE_SIZE])
			return null
	var scene := doc.generate_scene(state)
	if scene == null:
		errors.append("model '%s' is empty" % name)
		return null
	var root := Node3D.new()
	root.name = name
	_keep_meshes(scene, root, Transform3D.IDENTITY)
	scene.free()
	apply_vertex_colors(root)
	var triangles := 0
	for mi in root.get_children():
		triangles += triangle_count((mi as MeshInstance3D).mesh)
	if triangles > MAX_TRIANGLES:
		errors.append("model '%s' has %d triangles (max %d)" % [name, triangles, MAX_TRIANGLES])
		root.free()
		return null
	return root

## Copies every mesh of the generated glTF scene directly under root (with its full transform); nothing else.
static func _keep_meshes(node: Node, root: Node3D, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		mesh = (node as ImporterMeshInstance3D).mesh.get_mesh()
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.name = node.name
		mi.mesh = mesh
		mi.transform = xf
		root.add_child(mi)
	for c in node.get_children():
		_keep_meshes(c, root, xf)

## glTF rule: vertex colors (COLOR_0) always tint the base color. Godot's reader leaves them unused, so every
## surface that has vertex colors gets its own material copy with "vertex color as albedo" on.
static func apply_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var colors: Variant = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if colors is PackedColorArray and not (colors as PackedColorArray).is_empty() and mat != null 						and not mat.vertex_color_use_as_albedo:
					var copy := mat.duplicate() as BaseMaterial3D
					copy.vertex_color_use_as_albedo = true
					mi.set_surface_override_material(s, copy)
	for c in node.get_children():
		apply_vertex_colors(c)

static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
			n += floori((indices as PackedInt32Array).size() / 3.0)
		else:
			n += floori((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
	return n

## The .glb container is well-formed and refers to no outside files (buffers / images must be embedded).
static func check_glb(bytes: PackedByteArray, errors: Array[String]) -> bool:
	if bytes.size() < 20 or bytes.decode_u32(0) != GLB_MAGIC or bytes.decode_u32(4) != 2:
		errors.append("not a binary glTF 2.0 (.glb) file")
		return false
	if bytes.decode_u32(8) != bytes.size():
		errors.append("glb length mismatch")
		return false
	var json_len := bytes.decode_u32(12)
	if bytes.decode_u32(16) != GLB_JSON_CHUNK or 20 + json_len > bytes.size():
		errors.append("glb has no JSON chunk")
		return false
	var json := JSON.new()
	if json.parse(bytes.slice(20, 20 + json_len).get_string_from_utf8()) != OK or not json.data is Dictionary:
		errors.append("glb JSON is invalid")
		return false
	var gltf: Dictionary = json.data
	for key: String in ["buffers", "images"]:
		var list: Variant = gltf.get(key, [])
		if not list is Array:
			return false
		for entry: Variant in list:
			if entry is Dictionary and (entry as Dictionary).has("uri"):
				var uri: Variant = (entry as Dictionary)["uri"]
				if not (uri is String and (uri as String).begins_with("data:")):
					errors.append("glb refers to an outside file (%s) — export with everything embedded" % key)
					return false
	return true
