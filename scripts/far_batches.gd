extends Node
## Distance batches (HLOD) for small static set pieces.
## Beyond SWITCH_DISTANCE most of the frame was hundreds of props a few pixels
## wide, each its own draw call: cutting the view at 30 m took the opening from
## ~800 draw calls to ~165. Instead of hiding them, every small static mesh also
## gets a far copy: identical geometry merged by material into 16 m cells. The
## renderer shows the merged cell while the camera is farther than
## SWITCH_DISTANCE from its centre and the original pieces when closer
## (visibility_parent), so nothing appears or vanishes.
##
## Story code keeps full control over the originals: a sweep checks a few pieces
## per frame, rebuilds a cell when one is hidden or shown, and drops a piece from
## batching for good once it moves.
var game
const CELL := 16.0
const SWITCH_DISTANCE := 24.0
const MAX_PIECE := 10.0
const FIRST_BUILD := .6
const SWEEP_PER_FRAME := 48
const REBUILDS_PER_FRAME := 2

# key -> {node: MeshInstance3D, members: Array[MeshInstance3D], dirty: bool}
var cells := {}
# member -> [key, global_transform, visible]
var members := {}
var sweep_list: Array = []
var sweep_index := 0
var start_clock := 0.0
var built := false
var last_phase := ""
var holder: Node3D

func setup(owner_game) -> void:
	game = owner_game

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	if not built:
		start_clock += delta
		if start_clock < FIRST_BUILD: return
		built = true; last_phase = game.phase
		holder = Node3D.new(); holder.name = "FarBatches"; game.world.add_child(holder)
		collect()
	elif game.phase != last_phase:
		last_phase = game.phase
		collect()
	sweep()
	var rebuilt := 0
	for key in cells:
		if rebuilt >= REBUILDS_PER_FRAME: break
		if cells[key].dirty:
			rebuild(key); rebuilt += 1

func excluded(node: Node) -> bool:
	if not is_instance_valid(game.player) or game.player.is_ancestor_of(node): return true
	if is_instance_valid(game.mirror_system) and game.mirror_system.is_ancestor_of(node): return true
	for id in game.actors:
		if game.actors[id].is_ancestor_of(node): return true
	var ancestor := node
	while ancestor != null and ancestor != game:
		if ancestor.get_meta("dynamic_set", false): return true
		if ancestor is Skeleton3D or ancestor is AnimationMixer or ancestor is PhysicsBody3D and not ancestor is StaticBody3D: return true
		# Doors and other interactables move or highlight as a unit.
		if ancestor is CollisionObject3D and "interaction_id" in ancestor: return true
		ancestor = ancestor.get_parent()
	return false

func batchable_material(material: Material) -> bool:
	if not material is BaseMaterial3D: return false
	var base := material as BaseMaterial3D
	if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	if base.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or base.grow: return false
	# Object-space triplanar mapping would shift once vertices are baked.
	if base.uv1_triplanar and not base.uv1_world_triplanar: return false
	if base.uv2_triplanar and not base.uv2_world_triplanar: return false
	return true

func candidate(item: MeshInstance3D) -> bool:
	if item.mesh == null or item.skeleton != NodePath("") or item.layers != 1: return false
	if item == holder or holder.is_ancestor_of(item): return false
	if item.visibility_range_begin > 0 or item.visibility_range_end > 0 or item.visibility_parent != NodePath(""): return false
	if not item.is_visible_in_tree(): return false
	var box := item.global_transform * item.get_aabb()
	if maxf(box.size.x, maxf(box.size.y, box.size.z)) > MAX_PIECE: return false
	for surface in item.mesh.get_surface_count():
		if not batchable_material(item.get_active_material(surface)): return false
	return not excluded(item)

func cell_key(item: MeshInstance3D) -> Vector3i:
	var centre := (item.global_transform * item.get_aabb()).get_center()
	return Vector3i(floori(centre.x / CELL), floori(centre.y / CELL), floori(centre.z / CELL))

func collect() -> void:
	for node in game.world.find_children("*", "MeshInstance3D", true, false):
		if members.has(node) or not candidate(node): continue
		var key := cell_key(node)
		if not cells.has(key):
			var far := MeshInstance3D.new(); far.name = "FarCell"
			far.visibility_range_begin = SWITCH_DISTANCE
			far.visibility_range_begin_margin = 1.0
			holder.add_child(far)
			cells[key] = {"node": far, "members": [], "dirty": true}
		cells[key].members.append(node)
		cells[key].dirty = true
		members[node] = [key, node.global_transform, true]
		sweep_list.append(node)
	for key in cells:
		if cells[key].dirty: rebuild(key)

# One surface per (material, shadow casting, vertex format); each becomes one draw.
func rebuild(key: Vector3i) -> void:
	var cell: Dictionary = cells[key]
	cell.dirty = false
	var far: MeshInstance3D = cell.node
	var kept: Array = []
	var bounds := AABB()
	var first := true
	for item in cell.members:
		if not is_instance_valid(item) or not members.has(item): continue
		kept.append(item)
		var box: AABB = item.global_transform * item.get_aabb()
		bounds = box if first else bounds.merge(box); first = false
	cell.members = kept
	if kept.is_empty():
		far.mesh = null; return
	# The far node sits at the cell centre: visibility ranges measure from it.
	far.global_transform = Transform3D(Basis.IDENTITY, bounds.get_center())
	var to_local := far.global_transform.affine_inverse()
	var groups := {}
	var shadows := false
	for item in kept:
		var visible: bool = item.is_visible_in_tree()
		members[item][2] = visible
		if item.visibility_parent == NodePath(""): item.visibility_parent = item.get_path_to(far)
		if not visible: continue
		if item.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: shadows = true
		for surface in item.mesh.get_surface_count():
			var material: Material = item.get_active_material(surface)
			var format: int = surface_format(item.mesh, surface)
			var group := "%d:%d" % [material.get_instance_id(), format]
			if not groups.has(group): groups[group] = [material, []]
			groups[group][1].append([item, surface])
	var mesh := ArrayMesh.new()
	for group in groups:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry in groups[group][1]:
			builder.append_from(entry[0].mesh, entry[1], to_local * entry[0].global_transform)
		builder.set_material(groups[group][0])
		builder.commit(mesh)
	far.mesh = mesh
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# Vertex attributes decide which surfaces SurfaceTool can merge. Primitive meshes
# lack surface_get_format(), so ask the server once per mesh and surface.
var formats := {}
func surface_format(mesh: Mesh, surface: int) -> int:
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	if not formats.has(key):
		var format: int = RenderingServer.mesh_get_surface(mesh.get_rid(), surface).get("format", 0)
		formats[key] = format & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2)
	return formats[key]

# Round-robin check of a few pieces per frame, so story changes reach the far copy.
func sweep() -> void:
	if sweep_list.is_empty(): return
	for step in mini(SWEEP_PER_FRAME, sweep_list.size()):
		sweep_index = (sweep_index + 1) % sweep_list.size()
		var item = sweep_list[sweep_index]
		if not is_instance_valid(item):
			continue
		var state: Array = members.get(item, [])
		if state.is_empty(): continue
		if not item.global_transform.is_equal_approx(state[1]):
			# A piece that moves is no longer static: it leaves batching for good.
			members.erase(item)
			item.visibility_parent = NodePath("")
			cells[state[0]].dirty = true
		elif item.is_visible_in_tree() != state[2]:
			cells[state[0]].dirty = true
	if sweep_index == 0:
		sweep_list = sweep_list.filter(func(item): return is_instance_valid(item) and members.has(item))
		if sweep_list.is_empty(): sweep_index = 0
		else: sweep_index = sweep_index % sweep_list.size()
