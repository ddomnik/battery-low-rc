class_name MapCatalog
## The maps the game can play: every folder in res://maps/ with a map.json (built-in maps).
## Later, maps received in a lobby will live in user://maps/ and go through the same loader.

const BUILTIN_DIR := "res://maps/"
const MAP_FILE := "map.json"
const DEFAULT_ID := "test_arena"

## [{"id": String, "name": String}] for every map that loads, default map first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in DirAccess.get_directories_at(BUILTIN_DIR):
		if not valid_id(id):
			continue
		var map := load_map(id)
		if map != null:
			out.append({"id": id, "name": map.name})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["id"] == DEFAULT_ID or (b["id"] != DEFAULT_ID and String(a["name"]) < String(b["name"])))
	return out

## The validated map, or null (unknown id, unreadable or invalid file — problems are pushed as warnings).
static func load_map(id: String) -> MapData:
	if not valid_id(id):
		return null
	var path := BUILTIN_DIR + id + "/" + MAP_FILE
	if not FileAccess.file_exists(path):
		return null
	var errors: Array[String] = []
	var map := MapLoader.parse(FileAccess.get_file_as_string(path), id, errors)
	for e in errors:
		push_warning("Map '%s': %s" % [id, e])
	return map

## Map ids are folder names: lowercase letters, digits, "_" and "-" only (no path tricks like "../").
static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 40:
		return false
	for c in id:
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "_" and c != "-":
			return false
	return true
