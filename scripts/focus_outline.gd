extends Node
## Cache geometry lookups; only project the focused object's corners each frame.
var game
var bounds_cache: Dictionary = {}
const IMPORTED_MIRROR_PARTS := ["Mirror Frame", "Mirror surface", "Cylinder_009", "Cylinder_008"]

func setup(owner_game): game = owner_game

func cache_bounds(target: Node3D) -> Dictionary:
	var key := target.get_instance_id()
	if bounds_cache.has(key): return bounds_cache[key]
	var visuals: Array[MeshInstance3D] = []
	if target.has_node("CharacterArt"):
		for mesh in target.get_node("CharacterArt").find_children("*", "MeshInstance3D", true, false):
			visuals.append(mesh)
	elif target.has_meta("source_mesh"):
		# Every imported hit surface represents the same complete standing mirror.
		var names: Array = IMPORTED_MIRROR_PARTS if String(target.get_meta("source_mesh")) in IMPORTED_MIRROR_PARTS else [String(target.get_meta("source_mesh"))]
		for mesh_name in names:
			var source = game.model.find_child(mesh_name, true, false)
			if source is MeshInstance3D: visuals.append(source)
	else:
		for mesh in target.find_children("*", "MeshInstance3D", true, false): visuals.append(mesh)
	var meshes: Array = []
	for mesh in visuals: meshes.append(bounds_entry(mesh, mesh.get_aabb()))
	var shapes: Array = []
	for shape in target.find_children("*", "CollisionShape3D", true, false):
		if shape.shape: shapes.append(bounds_entry(shape, shape.shape.get_debug_mesh().get_aabb()))
	var result := {"meshes": meshes, "shapes": shapes}
	bounds_cache[key] = result
	return result

func bounds_entry(node: Node3D, bounds: AABB) -> Dictionary:
	var corners := PackedVector3Array()
	for i in 8: corners.append(bounds.get_endpoint(i))
	return {"node": node, "corners": corners}

func _process(_delta):
	if not is_instance_valid(game): return
	var target: Node3D = game.player.focus as Node3D
	if not is_instance_valid(target) or game.player.locked:
		game.hud.set_focus_bounds(Rect2()); return
	var cached := cache_bounds(target)
	var entries: Array = cached.meshes
	var visible_mesh := false
	for entry in entries:
		if is_instance_valid(entry.node) and entry.node.is_visible_in_tree():
			visible_mesh = true; break
	if not visible_mesh: entries = cached.shapes
	var box := Rect2()
	var first := true
	for entry in entries:
		var node: Node3D = entry.node
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var transform := node.global_transform
		for corner in entry.corners:
			var point: Vector3 = transform * corner
			if game.player.camera.is_position_behind(point): continue
			var screen: Vector2 = game.player.camera.unproject_position(point)
			if first: box = Rect2(screen, Vector2.ZERO); first = false
			else: box = box.expand(screen)
	if first:
		game.hud.set_focus_bounds(Rect2()); return
	var ratio: Vector2 = game.hud.root.size / get_viewport().get_visible_rect().size
	box = Rect2(box.position * ratio, box.size * ratio).grow(8)
	box = box.intersection(Rect2(Vector2(12, 12), game.hud.root.size - Vector2(24, 24)))
	game.hud.set_focus_bounds(box)
