extends Node
## Splits large static meshes into tiles so each tile gets its own short light list.
## The Compatibility renderer picks lights per object and caps the list at
## max_lights_per_object (24). The floor, canvas, roof and ring each span the
## whole tent, so every pixel of them looped over 24 lights while 3-5 actually
## reached it, and lights past the cap were dropped even right above the floor.
## On a Mali-G615 the lamps took ~10 ms of the opening's 27 ms frame.
##
## Tiles keep the original vertices in the original's local space and hang under
## it with an identity transform, so they inherit its placement and visibility
## (story code still toggles the original). The original stays in the tree with
## its mesh, colliders and bounds, but renders on no layer.
var game
const CELL := 12.0
# Meshes smaller than this across (XZ, metres) keep a short light list already.
const MIN_SIZE := 18.0
const FIRST_RUN := .9
const MAX_DEPTH := 6

var start_clock := 0.0
var done := false
var last_phase := ""
# Slicing runs on a worker thread: on a phone the opening froze for seconds.
var task := -1
var jobs: Array = []

func setup(owner_game) -> void:
	game = owner_game

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	if task >= 0:
		if not WorkerThreadPool.is_task_completed(task): return
		WorkerThreadPool.wait_for_task_completion(task); task = -1
	if not jobs.is_empty():
		finish()
		# Portal culling collected before the tiles existed; let it look again.
		var zones := get_parent().get_node_or_null("ZoneCulling")
		if jobs.is_empty() and zones: zones.collected = false
		return
	if not done:
		start_clock += delta
		if start_clock < FIRST_RUN: return
		done = true; last_phase = game.phase
		start()
	elif game.phase != last_phase:
		last_phase = game.phase
		start()

func excluded(node: Node) -> bool:
	if is_instance_valid(game.player) and game.player.is_ancestor_of(node): return true
	if is_instance_valid(game.mirror_system) and game.mirror_system.is_ancestor_of(node): return true
	for id in game.actors:
		if game.actors[id].is_ancestor_of(node): return true
	var ancestor := node
	while ancestor != null and ancestor != game:
		if ancestor.get_meta("dynamic_set", false): return true
		if ancestor is Skeleton3D or ancestor is AnimationMixer or ancestor is CharacterBody3D or ancestor is AnimatableBody3D or ancestor is RigidBody3D: return true
		if ancestor is CollisionObject3D and "interaction_id" in ancestor: return true
		ancestor = ancestor.get_parent()
	return false

func candidate(item: MeshInstance3D) -> bool:
	if item.has_meta("light_tiled") or item.has_meta("light_tile"): return false
	if item.mesh == null or item.skeleton != NodePath("") or item.layers == 0: return false
	if item.mesh is ArrayMesh and item.mesh.get_blend_shape_count() > 0: return false
	var box := item.global_transform * item.get_aabb()
	if maxf(box.size.x, box.size.z) < MIN_SIZE: return false
	return not excluded(item)

# Main thread: gather mesh data. Worker: slice. Main thread again: add tiles.
func start() -> void:
	jobs.clear()
	for node in game.world.find_children("*", "MeshInstance3D", true, false):
		if not candidate(node): continue
		var mesh: Mesh = node.mesh
		var surfaces: Array = []
		var ok := true
		for surface in mesh.get_surface_count():
			var info: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
			if int(info.get("primitive", RenderingServer.PRIMITIVE_TRIANGLES)) != RenderingServer.PRIMITIVE_TRIANGLES: ok = false; break
			var arrays: Array = mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_CUSTOM0] != null: ok = false; break
			surfaces.append(arrays)
		if ok: jobs.append({"item": node, "transform": node.global_transform, "surfaces": surfaces, "cells": {}})
	if jobs.is_empty(): return
	task = WorkerThreadPool.add_task(slice_all)

func slice_all() -> void:
	for job in jobs: job.cells = slice(job.surfaces, job.transform)

# Adds tiles for a few meshes per frame, within FINISH_BUDGET milliseconds.
const FINISH_BUDGET := 6
func finish() -> void:
	var started := Time.get_ticks_msec()
	while not jobs.is_empty() and Time.get_ticks_msec() - started < FINISH_BUDGET:
		var job: Dictionary = jobs.pop_back()
		var item = job.item
		if not is_instance_valid(item) or item.layers == 0 or job.cells.size() < 2: continue
		if not item.global_transform.is_equal_approx(job.transform): continue
		var cells: Dictionary = job.cells
		for key in cells:
			var tile_mesh := ArrayMesh.new()
			for entry in cells[key]:
				tile_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, entry[1])
				tile_mesh.surface_set_material(tile_mesh.get_surface_count() - 1, item.get_active_material(entry[0]))
			var piece := MeshInstance3D.new()
			piece.name = "LightTile"
			piece.set_meta("light_tile", true)
			piece.mesh = tile_mesh
			piece.layers = item.layers
			piece.cast_shadow = item.cast_shadow
			piece.material_overlay = item.material_overlay
			piece.transparency = item.transparency
			piece.extra_cull_margin = item.extra_cull_margin
			piece.sorting_offset = item.sorting_offset
			piece.visibility_range_begin = item.visibility_range_begin
			piece.visibility_range_end = item.visibility_range_end
			item.add_child(piece)
		item.set_meta("light_tiled", item.layers)
		item.layers = 0

# Returns cell -> [[surface, compacted arrays], ...]. Touches no nodes.
func slice(surfaces: Array, to_world: Transform3D) -> Dictionary:
	var cells := {}
	for surface in surfaces.size():
		var split := subdivide(surfaces[surface], to_world)
		var points: PackedVector3Array = split[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = split[Mesh.ARRAY_INDEX]
		var binned := {}
		for t in range(0, indices.size(), 3):
			var centre := to_world * ((points[indices[t]] + points[indices[t + 1]] + points[indices[t + 2]]) / 3.0)
			var key := Vector2i(floori(centre.x / CELL), floori(centre.z / CELL))
			if not binned.has(key): binned[key] = PackedInt32Array()
			binned[key].append_array([indices[t], indices[t + 1], indices[t + 2]])
		for key in binned:
			if not cells.has(key): cells[key] = []
			cells[key].append([surface, compact(split, binned[key])])
	return cells

# Splits triangles longer than a cell into four, so huge quads such as the floor
# can be divided between tiles. Every vertex attribute is interpolated.
func subdivide(source: Array, to_world: Transform3D) -> Array:
	var arrays := source.duplicate()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for i in points.size(): indices.append(i)
	var long := false
	for t in range(0, indices.size(), 3):
		if longest(to_world, points, indices[t], indices[t + 1], indices[t + 2]) > CELL: long = true; break
	if not long:
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays
	var midpoints := {}
	var stack: Array = []
	for t in range(0, indices.size(), 3): stack.append([indices[t], indices[t + 1], indices[t + 2], 0])
	var result := PackedInt32Array()
	while not stack.is_empty():
		var tri: Array = stack.pop_back()
		points = arrays[Mesh.ARRAY_VERTEX]
		if tri[3] >= MAX_DEPTH or longest(to_world, points, tri[0], tri[1], tri[2]) <= CELL:
			result.append_array([tri[0], tri[1], tri[2]]); continue
		var ab := midpoint(arrays, midpoints, tri[0], tri[1])
		var bc := midpoint(arrays, midpoints, tri[1], tri[2])
		var ca := midpoint(arrays, midpoints, tri[2], tri[0])
		var depth: int = tri[3] + 1
		stack.append([tri[0], ab, ca, depth]); stack.append([ab, tri[1], bc, depth])
		stack.append([ca, bc, tri[2], depth]); stack.append([ab, bc, ca, depth])
	arrays[Mesh.ARRAY_INDEX] = result
	return arrays

func longest(to_world: Transform3D, points: PackedVector3Array, a: int, b: int, c: int) -> float:
	var pa := to_world * points[a]; var pb := to_world * points[b]; var pc := to_world * points[c]
	return maxf(pa.distance_to(pb), maxf(pb.distance_to(pc), pc.distance_to(pa)))

func midpoint(arrays: Array, cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key): return cache[key]
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index := points.size()
	points.append((points[a] + points[b]) * .5); arrays[Mesh.ARRAY_VERTEX] = points
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		normals.append((normals[a] + normals[b]).normalized()); arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var direction := (Vector3(tangents[a * 4], tangents[a * 4 + 1], tangents[a * 4 + 2]) + Vector3(tangents[b * 4], tangents[b * 4 + 1], tangents[b * 4 + 2])).normalized()
		tangents.append_array([direction.x, direction.y, direction.z, tangents[a * 4 + 3]]); arrays[Mesh.ARRAY_TANGENT] = tangents
	if arrays[Mesh.ARRAY_COLOR] != null:
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		colors.append(colors[a].lerp(colors[b], .5)); arrays[Mesh.ARRAY_COLOR] = colors
	for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[channel] != null:
			var uvs: PackedVector2Array = arrays[channel]
			uvs.append((uvs[a] + uvs[b]) * .5); arrays[channel] = uvs
	cache[key] = index
	return index

# Keeps only the vertices a tile uses.
func compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var local := PackedInt32Array(); local.resize(indices.size())
	for i in indices.size():
		var old := indices[i]
		if not remap.has(old): remap[old] = order.size(); order.append(old)
		local[i] = remap[old]
	var out := []; out.resize(Mesh.ARRAY_MAX)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var new_points := PackedVector3Array(); new_points.resize(order.size())
	for i in order.size(): new_points[i] = points[order[i]]
	out[Mesh.ARRAY_VERTEX] = new_points
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var src: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]; var dst := PackedVector3Array(); dst.resize(order.size())
		for i in order.size(): dst[i] = src[order[i]]
		out[Mesh.ARRAY_NORMAL] = dst
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var src: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]; var dst := PackedFloat32Array(); dst.resize(order.size() * 4)
		for i in order.size():
			for k in 4: dst[i * 4 + k] = src[order[i] * 4 + k]
		out[Mesh.ARRAY_TANGENT] = dst
	if arrays[Mesh.ARRAY_COLOR] != null:
		var src: PackedColorArray = arrays[Mesh.ARRAY_COLOR]; var dst := PackedColorArray(); dst.resize(order.size())
		for i in order.size(): dst[i] = src[order[i]]
		out[Mesh.ARRAY_COLOR] = dst
	for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[channel] != null:
			var src: PackedVector2Array = arrays[channel]; var dst := PackedVector2Array(); dst.resize(order.size())
			for i in order.size(): dst[i] = src[order[i]]
			out[channel] = dst
	out[Mesh.ARRAY_INDEX] = local
	return out
