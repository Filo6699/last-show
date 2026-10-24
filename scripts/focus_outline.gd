extends Node
## White geometry outline; projected bounds are only an invisible touch region.
var game
var bounds_cache: Dictionary = {}
var selected_meshes: Array[MeshInstance3D] = []
const OUTLINE_LAYER := 8
var previous_layers := {}
var glass_proxies: Array[MeshInstance3D] = []
var glass_material: StandardMaterial3D
var mirror_mask_world := World3D.new()
var mask_view: SubViewport
var mask_camera: Camera3D
var outline_rect: ColorRect
const IMPORTED_MIRROR_PARTS := ["Mirror Frame", "Mirror surface", "Cylinder_009", "Cylinder_008"]

func setup(owner_game):
	game = owner_game
	# Run after input and the frame's gameplay updates, so the mask camera,
	# projected bounds and focused target all describe the same view.
	process_priority = 100
	glass_material = StandardMaterial3D.new()
	glass_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mask_view = SubViewport.new()
	mask_view.transparent_bg = true
	mask_view.world_3d = game.get_world_3d()
	mask_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mask_view.positional_shadow_atlas_size = 0
	mask_view.msaa_3d = Viewport.MSAA_2X
	add_child(mask_view)
	mask_camera = Camera3D.new()
	mask_camera.cull_mask = OUTLINE_LAYER
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	mask_camera.environment = environment
	mask_view.add_child(mask_camera)
	var canvas := CanvasLayer.new()
	canvas.layer = 0
	add_child(canvas)
	outline_rect = ColorRect.new()
	outline_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/focus_outline.gdshader")
	material.set_shader_parameter("silhouette", mask_view.get_texture())
	outline_rect.material = material
	canvas.add_child(outline_rect)
	outline_rect.hide()

func highlight(entries: Array) -> void:
	var meshes: Array[MeshInstance3D] = []
	for entry in entries:
		if entry.node is MeshInstance3D and entry.node.is_visible_in_tree(): meshes.append(entry.node)
	if meshes == selected_meshes: return
	for mesh in selected_meshes:
		if is_instance_valid(mesh): mesh.layers = previous_layers.get(mesh.get_instance_id(), mesh.layers & ~OUTLINE_LAYER)
	for proxy in glass_proxies:
		proxy.hide()
		proxy.queue_free()
	glass_proxies.clear()
	previous_layers.clear()
	selected_meshes = meshes
	var has_glass := false
	for mesh in selected_meshes:
		if mesh.layers & 4: has_glass = true
	mask_view.world_3d = mirror_mask_world if has_glass else game.get_world_3d()
	for mesh in selected_meshes:
		previous_layers[mesh.get_instance_id()] = mesh.layers
		if has_glass:
			# Isolate reflective targets: Compatibility can leave the mask blank
			# when it shares the reflection world. Reuse geometry without its material.
			var proxy := MeshInstance3D.new()
			proxy.mesh = mesh.mesh
			proxy.material_override = glass_material
			proxy.layers = OUTLINE_LAYER
			proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mask_view.add_child(proxy)
			proxy.global_transform = mesh.global_transform
			glass_proxies.append(proxy)
		else:
			mesh.layers |= OUTLINE_LAYER
	outline_rect.visible = not selected_meshes.is_empty()
	mask_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if outline_rect.visible else SubViewport.UPDATE_DISABLED

func update_camera() -> void:
	var camera: Camera3D = game.player.camera
	# Half-resolution mask, capped at 720 pixels wide, renders only the selected object.
	var size := get_viewport().get_visible_rect().size
	var mask_size := Vector2i((size * minf(0.5, 720.0 / size.x)).round())
	if mask_view.size != mask_size: mask_view.size = mask_size
	mask_camera.global_transform = camera.global_transform
	mask_camera.fov = camera.fov
	mask_camera.near = camera.near
	mask_camera.far = camera.far
	mask_camera.keep_aspect = camera.keep_aspect

func _exit_tree():
	for mesh in selected_meshes:
		if is_instance_valid(mesh): mesh.layers = previous_layers.get(mesh.get_instance_id(), mesh.layers & ~OUTLINE_LAYER)

func cache_bounds(target: Node3D) -> Dictionary:
	var key := target.get_instance_id()
	if bounds_cache.has(key): return bounds_cache[key]
	var visuals: Array[MeshInstance3D] = []
	if target.has_node("CharacterArt"):
		for mesh in target.get_node("CharacterArt").find_children("*", "MeshInstance3D", true, false):
			visuals.append(mesh)
	elif target.has_meta("outline_meshes"):
		for mesh in target.get_meta("outline_meshes"):
			if is_instance_valid(mesh) and mesh is MeshInstance3D: visuals.append(mesh)
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
	if not is_instance_valid(target) or game.player.locked or game.hud.dialog.visible or game.hud.menu.visible:
		highlight([]); game.hud.set_focus_bounds(Rect2()); return
	var cached := cache_bounds(target)
	highlight(cached.meshes)
	if not selected_meshes.is_empty(): update_camera()
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
		highlight([]); game.hud.set_focus_bounds(Rect2()); return
	var ratio: Vector2 = game.hud.root.size / get_viewport().get_visible_rect().size
	box = Rect2(box.position * ratio, box.size * ratio).grow(8)
	box = box.intersection(Rect2(Vector2(12, 12), game.hud.root.size - Vector2(24, 24)))
	game.hud.set_focus_bounds(box)
	# Restrict the nine texture samples per pixel to the target's projected area.
	# Canvas coordinates match the HUD; mask UVs remain in the full camera image.
	outline_rect.position = box.position
	outline_rect.size = box.size
	var screen_size: Vector2 = game.hud.root.size
	outline_rect.material.set_shader_parameter("mask_rect", Vector4(
		box.position.x / screen_size.x, box.position.y / screen_size.y,
		box.size.x / screen_size.x, box.size.y / screen_size.y))
