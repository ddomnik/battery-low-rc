class_name PropCatalog
## The 3D models a map may place ("prop" objects). A map only ever names an id — "<pack>/<model>", e.g.
## "nature/tree_oak" — never a file path, so it can only use these trusted, built-in models.
## Every .glb in a pack folder is available under its file name.

const PACKS := {
	"nature": "res://assets/kenney_nature_kit/",
}

static var _paths: Dictionary = {}   # id → res:// path (filled on first use)

static func has(id: String) -> bool:
	_scan()
	return _paths.has(id)

static func ids() -> PackedStringArray:
	_scan()
	var out := PackedStringArray(_paths.keys())
	out.sort()
	return out

## The id of a catalog model file ("res://assets/kenney_nature_kit/tree_oak.glb" → "nature/tree_oak"), or "".
static func id_for_path(path: String) -> String:
	_scan()
	for id: String in _paths:
		if _paths[id] == path:
			return id
	return ""

## A new instance of the model, or null for an unknown id.
static func instantiate(id: String) -> Node3D:
	_scan()
	if not _paths.has(id):
		return null
	var scene := load(_paths[id]) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

static func _scan() -> void:
	if not _paths.is_empty():
		return
	for pack: String in PACKS:
		var dir: String = PACKS[pack]
		for file in DirAccess.get_files_at(dir):
			# Exported builds list "x.glb.import" instead of "x.glb".
			var name := file.trim_suffix(".import")
			if name.get_extension() == "glb":
				_paths["%s/%s" % [pack, name.get_basename()]] = dir + name
