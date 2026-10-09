@tool
extends EditorScenePostImport
## Import script for map models painted with vertex colors (Blender "Color Attributes"): Godot's importer leaves
## them unused, the game shows them (glTF rule, see MapModels.apply_vertex_colors). With this script the editor
## preview matches. Use: select the .glb → Import dock → Import Script → this file → Reimport.

func _post_import(scene: Node) -> Object:
	_enable(scene)
	return scene

func _enable(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var colors: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if colors is PackedColorArray and not (colors as PackedColorArray).is_empty() and mat != null:
				mat.vertex_color_use_as_albedo = true
	for c in node.get_children():
		_enable(c)
