extends Node3D
## Small, render-only dressing for the supplied canopy tear and the generated
## maintenance catwalk. It adds no collision or movement logic.

var game: Node
var stage_show: Node3D
var late: Node

const METAL_COLOR := Color("465751")
const METAL_DARK := Color("34423e")


func setup(owner_game: Node, owner_stage_show: Node3D) -> void:
	game = owner_game
	stage_show = owner_stage_show
	name = "CanopyDamageFinish"
	stage_show.add_child(self)
	call_deferred("_build_after_world_setup")


func _build_after_world_setup() -> void:
	# location.setup creates the stage before full_game creates the upper catwalk.
	# Wait until that synchronous setup has completed before adding its fittings.
	await get_tree().physics_frame
	if not is_instance_valid(game) or not is_instance_valid(stage_show):
		return
	late = game.full_game.late
	_move_breach_over_trampoline()
	await get_tree().physics_frame
	if not is_instance_valid(game):
		return
	_patch_canopy_slot()
	_build_irregular_cut_edge()
	_build_catwalk_joints()
	_replace_legacy_flap()
	sync_damage()


func sync_damage() -> void:
	# The stitched static border follows the source hole. The moving flap remains
	# the original stage node, so stage_show keeps control of its tested state.
	visible = true


func _replace_legacy_flap() -> void:
	var flap: MeshInstance3D = stage_show.get("loose_canvas")
	if not is_instance_valid(flap):
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array([
		Vector3(-.02, 0, .08), Vector3(-.34, .20, .27), Vector3(-1.16, .08, .12),
		Vector3(-1.42, -.02, .55), Vector3(-2.55, .18, .68), Vector3(-3.15, .03, .32),
		Vector3(-.30, .10, .50), Vector3(-.55, .30, 1.24), Vector3(-1.27, .13, 1.62),
		Vector3(-1.76, .02, 1.45), Vector3(-2.28, .21, 2.35), Vector3(-2.95, .06, 2.89),
		Vector3(-.85, .03, 2.52), Vector3(-1.24, .19, 2.84), Vector3(-1.72, .04, 2.56)
	])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN,
		Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN,
		Vector3.DOWN, Vector3.DOWN, Vector3.DOWN
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 1, 6, 1, 7, 6, 1, 2, 7, 2, 8, 7, 2, 3, 8,
		3, 9, 8, 3, 4, 9, 4, 10, 9, 4, 5, 10, 5, 11, 10,
		7, 8, 12, 8, 13, 12, 8, 9, 13, 9, 14, 13
	])
	var folded := ArrayMesh.new()
	folded.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	flap.mesh = folded
	var folded_material := _material(Color("713640"))
	folded_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flap.material_override = folded_material
	flap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# The supplied canopy came cut near the king pole, over the west catwalk. The
# story needs one opening, straight above the trampoline on the east deck, so
# Richard bounces up through it. Close the old cut with the mirror image of the
# intact canvas across x=0 (the canopy is mirror-symmetric there; mirroring
# swaps which material each stripe uses), then cut the new opening.
const OLD_BREACH_X := Vector2(-11.4, -4.5)
const OLD_BREACH_Z := Vector2(-9.4, -2.5)

func _move_breach_over_trampoline() -> void:
	var source: MeshInstance3D = game.model.find_child("Шатер - главный_001", true, false)
	if not is_instance_valid(source) or source.mesh == null or source.mesh.get_surface_count() != 2:
		return
	var new_x: Vector2 = stage_show.ROOF_BREACH_X_RANGE
	var new_z: Vector2 = stage_show.ROOF_BREACH_Z_RANGE
	var to_world := source.global_transform
	var to_local := to_world.affine_inverse()
	var empty := {}
	var surfaces: Array = []
	for index in 2:
		surfaces.append(source.mesh.surface_get_arrays(index))
	var built: Array = [[], []]
	var cut_pieces: Array = [[], []]
	for index in 2:
		var arrays: Array = surfaces[index]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var corners: Array[Vector3] = []
			for k in 3: corners.append(to_world * vertices[indices[t + k]])
			var centre: Vector3 = (corners[0] + corners[1] + corners[2]) / 3.0
			# Keep the triangle unless it reaches the new opening; those are
			# split finely and only the pieces outside the opening survive.
			var cut := Rect2(new_x.x, new_z.x, new_x.y - new_x.x, new_z.y - new_z.x)
			if centre.y > 44.0 and _triangle_touches(corners, cut.grow(.05)):
				for piece in _split_outside(corners, cut, .25):
					cut_pieces[index].append(piece)
			else:
				built[index].append([indices[t], indices[t + 1], indices[t + 2], false])
			# Mirror it into the old cut where that cut has no canvas.
			var covers := false
			var samples: Array[Vector3] = [centre]
			for a in 9:
				for b in 9 - a:
					samples.append(corners[0] + (corners[1] - corners[0]) * (a / 8.0) + (corners[2] - corners[0]) * (b / 8.0))
			for sample in samples:
				var mirrored := Vector3(-sample.x, sample.y, sample.z)
				if mirrored.y < 44.0 or mirrored.x < OLD_BREACH_X.x or mirrored.x > OLD_BREACH_X.y or mirrored.z < OLD_BREACH_Z.x or mirrored.z > OLD_BREACH_Z.y:
					continue
				var key := Vector2i(roundi(mirrored.x * 4.0), roundi(mirrored.z * 4.0))
				if not empty.has(key): empty[key] = _surface_at(mirrored.x, mirrored.z).is_empty()
				if empty[key]:
					covers = true
					break
			if covers:
				built[1 - index].append([indices[t], indices[t + 1], indices[t + 2], true, index])
	var mesh := ArrayMesh.new()
	var faces := PackedVector3Array()
	for index in 2:
		var own: Array = surfaces[index]
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var out_uv := PackedVector2Array()
		for triangle in built[index]:
			var from: Array = surfaces[triangle[4]] if triangle[3] else own
			var order := [0, 2, 1] if triangle[3] else [0, 1, 2]
			for k in order:
				var vertex: Vector3 = from[Mesh.ARRAY_VERTEX][triangle[k]]
				var normal: Vector3 = from[Mesh.ARRAY_NORMAL][triangle[k]]
				if triangle[3]:
					# A few centimetres outside, so the original canvas wins
					# wherever the copy overlaps it.
					var world := to_world * vertex
					vertex = to_local * Vector3(-world.x, world.y + .03, world.z)
					var world_normal := to_world.basis * normal
					normal = (to_local.basis * Vector3(-world_normal.x, world_normal.y, world_normal.z)).normalized()
				out_v.append(vertex)
				out_n.append(normal)
				out_uv.append(from[Mesh.ARRAY_TEX_UV][triangle[k]])
				faces.append(to_world * vertex)
		var flat_normal: Vector3 = own[Mesh.ARRAY_NORMAL][0]
		for piece in cut_pieces[index]:
			var normal: Vector3 = (to_local.basis * (piece[1] - piece[0]).cross(piece[2] - piece[0])).normalized()
			for point in piece:
				out_v.append(to_local * point)
				out_n.append(normal if normal.length_squared() > .5 else flat_normal)
				out_uv.append(Vector2(0, 1))
				faces.append(point)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = out_v
		arrays[Mesh.ARRAY_NORMAL] = out_n
		arrays[Mesh.ARRAY_TEX_UV] = out_uv
		# Other code reads the canopy as an indexed mesh.
		var sequence := PackedInt32Array()
		for i in out_v.size(): sequence.append(i)
		arrays[Mesh.ARRAY_INDEX] = sequence
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var materials := [source.get_active_material(0), source.get_active_material(1)]
	source.mesh = mesh
	for index in 2: source.set_surface_override_material(index, materials[index])
	for body in game.model.find_children("*", "StaticBody3D", true, false):
		if String(body.get_meta("source_mesh", "")) != String(source.name): continue
		var shape := body.get_child(0) as CollisionShape3D
		if shape == null or not shape.shape is ConcavePolygonShape3D: continue
		var local_faces := PackedVector3Array()
		var inverse: Transform3D = shape.global_transform.affine_inverse()
		for point in faces: local_faces.append(inverse * point)
		shape.shape.set_faces(local_faces)
	# The canvas occluder was built from the old triangles; it would now hide
	# the sky through the new opening.
	for occluder in source.find_children("*", "OccluderInstance3D", false, false):
		var occlusion := ArrayOccluder3D.new()
		var points := PackedVector3Array()
		for point in faces: points.append(to_local * point)
		var order := PackedInt32Array()
		for i in points.size(): order.append(i)
		occlusion.set_arrays(points, order)
		occluder.occluder = occlusion


func _triangle_touches(corners: Array[Vector3], rect: Rect2) -> bool:
	var low := Vector2(minf(corners[0].x, minf(corners[1].x, corners[2].x)), minf(corners[0].z, minf(corners[1].z, corners[2].z)))
	var high := Vector2(maxf(corners[0].x, maxf(corners[1].x, corners[2].x)), maxf(corners[0].z, maxf(corners[1].z, corners[2].z)))
	return rect.intersects(Rect2(low, high - low))


# Halve the triangle's longest edge until the pieces are small, then drop the
# ones whose centre lies inside the opening.
func _split_outside(corners: Array[Vector3], rect: Rect2, size: float) -> Array:
	var result: Array = []
	var stack: Array = [corners]
	while not stack.is_empty():
		var tri: Array = stack.pop_back()
		var centre: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		if not _triangle_touches_array(tri, rect.grow(.05)):
			result.append(tri)
			continue
		var longest := 0
		var length := 0.0
		for k in 3:
			var edge: float = Vector2(tri[k].x - tri[(k + 1) % 3].x, tri[k].z - tri[(k + 1) % 3].z).length()
			if edge > length: length = edge; longest = k
		if length <= size:
			if not rect.has_point(Vector2(centre.x, centre.z)): result.append(tri)
			continue
		var a: Vector3 = tri[longest]
		var b: Vector3 = tri[(longest + 1) % 3]
		var c: Vector3 = tri[(longest + 2) % 3]
		var middle: Vector3 = (a + b) * .5
		stack.append([a, middle, c])
		stack.append([middle, b, c])
	return result


func _triangle_touches_array(tri: Array, rect: Rect2) -> bool:
	var typed: Array[Vector3] = [tri[0], tri[1], tri[2]]
	return _triangle_touches(typed, rect)


# The supplied canopy has a second, unintended gap: a long slot over the arena
# on the +Z side, running out from the king pole. Only the breach is meant to
# be open. Rebuild the canvas there: the canopy is mirror-symmetric across x=0,
# so across the slot its height follows h = A - B*x^2, fitted per row from the
# intact canvas either side. The stripes are radial from the pole and alternate
# between the two canvas materials; each cell copies the stripe found half a
# turn round the pole, where the canvas is intact.
const CANOPY_APEX := Vector3(0, 0, -10)
const SLOT_HALF_WIDTH := 4.8
const SLOT_Z := Vector2(0.0, 13.6)

func _patch_canopy_slot() -> void:
	var empty := {}
	var rows: Array[float] = []
	var heights: Array = []
	var steps_x := 24
	var z := SLOT_Z.x
	while z <= SLOT_Z.y + .001:
		rows.append(z)
		var near := _surface_at(5.5, z)
		var far := _surface_at(7.0, z)
		var row: Array[float] = []
		for i in steps_x + 1:
			var x := lerpf(-SLOT_HALF_WIDTH, SLOT_HALF_WIDTH, float(i) / steps_x)
			var y := 0.0
			if not near.is_empty() and not far.is_empty():
				var b: float = (near.position.y - far.position.y) / (49.0 - 30.25)
				y = near.position.y + b * 30.25 - b * x * x + .03
			row.append(y)
			empty[Vector2i(i, rows.size() - 1)] = _surface_at(x, z).is_empty()
		heights.append(row)
		z += .4
	var groups := {}
	var faces := PackedVector3Array()
	for r in rows.size() - 1:
		for i in steps_x:
			var gap := false
			for corner in [Vector2i(i, r), Vector2i(i + 1, r), Vector2i(i, r + 1), Vector2i(i + 1, r + 1)]:
				if empty[corner]: gap = true
			if not gap: continue
			var x0 := lerpf(-SLOT_HALF_WIDTH, SLOT_HALF_WIDTH, float(i) / steps_x)
			var x1 := lerpf(-SLOT_HALF_WIDTH, SLOT_HALF_WIDTH, float(i + 1) / steps_x)
			var quad: Array[Vector3] = [Vector3(x0, heights[r][i], rows[r]), Vector3(x1, heights[r][i + 1], rows[r]),
				Vector3(x1, heights[r + 1][i + 1], rows[r + 1]), Vector3(x0, heights[r + 1][i], rows[r + 1])]
			if quad.any(func(p): return p.y < 1.0): continue
			var centre: Vector3 = (quad[0] + quad[2]) * .5
			var opposite := CANOPY_APEX * 2.0 - centre
			var stripe := _sample_canopy(opposite.x, opposite.z)
			if stripe.is_empty(): continue
			var normal: Vector3 = (quad[1] - quad[0]).cross(quad[3] - quad[0]).normalized()
			if normal.y < 0: normal = -normal
			var flat_uv: Array[Vector2] = [Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)]
			_append_quad(groups, stripe.material, quad, flat_uv, -normal)
			for k in [0, 1, 2, 0, 2, 3]: faces.append(quad[k])
	if faces.is_empty(): return
	var patch := ArrayMesh.new()
	for key in groups:
		var data: Dictionary = groups[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_TEX_UV] = data.uvs
		arrays[Mesh.ARRAY_INDEX] = data.indices
		patch.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		patch.surface_set_material(patch.get_surface_count() - 1, data.material)
	var instance := MeshInstance3D.new()
	instance.name = "CanopySlotPatch"
	instance.mesh = patch
	add_child(instance)
	var body := StaticBody3D.new()
	body.name = "CanopySlotPatchCollision"
	body.set_meta("source_mesh", "Шатер - главный_001")
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	add_child(body)
	body.top_level = true
	body.global_transform = Transform3D.IDENTITY


func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	result.metallic = metallic
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result


func _surface_at(x: float, z: float) -> Dictionary:
	# The imported tent is curved and slopes sharply near the ridge. Sample the
	# real canopy collision rather than laying an assumed flat rectangle on it.
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 65.0, z), Vector3(x, 35.0, z), 1, [game.player.get_rid()])
	for attempt in 12:
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		if String(hit.collider.get_meta("source_mesh", "")).contains("Шатер"):
			return hit
		query.exclude.append(hit.collider.get_rid())
	return {}


func _build_irregular_cut_edge() -> void:
	var x_range: Vector2 = stage_show.get("ROOF_BREACH_X_RANGE")
	var z_range: Vector2 = stage_show.get("ROOF_BREACH_Z_RANGE")
	var groups: Dictionary = {}
	var edge_count := 20
	for side in [-1.0, 1.0]:
		var boundary_x := x_range.x if side < 0.0 else x_range.y
		var outward_x: float = side
		for i in edge_count:
			var z0 := lerpf(z_range.x, z_range.y, float(i) / edge_count)
			var z1 := lerpf(z_range.x, z_range.y, float(i + 1) / edge_count)
			var near0 := _sample_canopy(boundary_x + outward_x * .10, z0)
			var near1 := _sample_canopy(boundary_x + outward_x * .10, z1)
			var far0 := _sample_canopy(boundary_x + outward_x * .38, z0)
			var far1 := _sample_canopy(boundary_x + outward_x * .38, z1)
			_append_ripped_segment(groups, near0, near1, far0, far1, float(i), float(edge_count), float(side))
	for side in [-1.0, 1.0]:
		var boundary_z := z_range.x if side < 0.0 else z_range.y
		var outward_z: float = side
		for i in edge_count:
			var x0 := lerpf(x_range.x, x_range.y, float(i) / edge_count)
			var x1 := lerpf(x_range.x, x_range.y, float(i + 1) / edge_count)
			var near0 := _sample_canopy(x0, boundary_z + outward_z * .10)
			var near1 := _sample_canopy(x1, boundary_z + outward_z * .10)
			var far0 := _sample_canopy(x0, boundary_z + outward_z * .38)
			var far1 := _sample_canopy(x1, boundary_z + outward_z * .38)
			_append_ripped_segment(groups, near0, near1, far0, far1, float(i), float(edge_count), float(side + 2.0))
	_emit_ripped_meshes(groups)


func _sample_canopy(x: float, z: float) -> Dictionary:
	var hit := _surface_at(x, z)
	if hit.is_empty():
		return {}
	var source_name := String(hit.collider.get_meta("source_mesh", ""))
	var source: MeshInstance3D = game.model.find_child(source_name, true, false)
	if not is_instance_valid(source) or source.mesh == null:
		return {}
	var face_index: int = hit.face_index
	var first_face := 0
	for surface_index in source.mesh.get_surface_count():
		var arrays: Array = source.mesh.surface_get_arrays(surface_index)
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var face_count: int = (surface_indices.size() if not surface_indices.is_empty() else surface_vertices.size()) / 3
		if face_index >= first_face and face_index < first_face + face_count:
			var triangle := face_index - first_face
			var i0: int = surface_indices[triangle * 3] if not surface_indices.is_empty() else triangle * 3
			var i1: int = surface_indices[triangle * 3 + 1] if not surface_indices.is_empty() else triangle * 3 + 1
			var i2: int = surface_indices[triangle * 3 + 2] if not surface_indices.is_empty() else triangle * 3 + 2
			var p0: Vector3 = surface_vertices[i0]
			var p1: Vector3 = surface_vertices[i1]
			var p2: Vector3 = surface_vertices[i2]
			var local_hit: Vector3 = source.global_transform.affine_inverse() * hit.position
			var e0 := p1 - p0
			var e1 := p2 - p0
			var v := local_hit - p0
			var d00 := e0.dot(e0); var d01 := e0.dot(e1); var d11 := e1.dot(e1)
			var d20 := v.dot(e0); var d21 := v.dot(e1)
			var denom := d00 * d11 - d01 * d01
			if absf(denom) < .000001 or surface_uvs.size() != surface_vertices.size():
				return {}
			var b := (d11 * d20 - d01 * d21) / denom
			var c := (d00 * d21 - d01 * d20) / denom
			var a := 1.0 - b - c
			var uv: Vector2 = surface_uvs[i0] * a + surface_uvs[i1] * b + surface_uvs[i2] * c
			return {"position": hit.position, "normal": hit.normal, "uv": uv, "material": source.get_active_material(surface_index)}
		first_face += face_count
	return {}


func _append_ripped_segment(groups: Dictionary, near0: Dictionary, near1: Dictionary, far0: Dictionary, far1: Dictionary,
		segment: float, segment_count: float, phase: float) -> void:
	if near0.is_empty() or near1.is_empty() or far0.is_empty() or far1.is_empty():
		return
	var mat0: Material = near0.material
	var mat1: Material = near1.material
	if not is_instance_valid(mat0) or not is_instance_valid(mat1):
		return
	var direction0: Vector3 = (near0.position - far0.position).normalized()
	var direction1: Vector3 = (near1.position - far1.position).normalized()
	var edge0: float = _tear_depth(segment, segment_count, phase)
	var edge1: float = _tear_depth(segment + 1.0, segment_count, phase)
	var dist0: float = .12 + edge0
	var dist1: float = .12 + edge1
	var travel0: float = near0.position.distance_to(far0.position)
	var travel1: float = near1.position.distance_to(far1.position)
	if travel0 < .05 or travel1 < .05:
		return
	var target0: Vector3 = near0.position + direction0 * dist0 - near0.normal * .025
	var target1: Vector3 = near1.position + direction1 * dist1 - near1.normal * .025
	var uv_dir0: Vector2 = (near0.uv - far0.uv) / travel0
	var uv_dir1: Vector2 = (near1.uv - far1.uv) / travel1
	var uv0: Vector2 = near0.uv + uv_dir0 * dist0
	var uv1: Vector2 = near1.uv + uv_dir1 * dist1
	var near_mid: Vector3 = near0.position.lerp(near1.position, .5) - near0.normal.lerp(near1.normal, .5) * .025
	var target_mid: Vector3 = target0.lerp(target1, .5)
	var uv_near_mid: Vector2 = near0.uv.lerp(near1.uv, .5)
	var uv_target_mid: Vector2 = uv0.lerp(uv1, .5)
	var normal_mid: Vector3 = near0.normal.lerp(near1.normal, .5).normalized()
	_append_quad(groups, mat0,
		[near0.position - near0.normal * .025, near_mid, target_mid, target0],
		[near0.uv, uv_near_mid, uv_target_mid, uv0], near0.normal)
	_append_quad(groups, mat1,
		[near_mid, near1.position - near1.normal * .025, target1, target_mid],
		[uv_near_mid, near1.uv, uv1, uv_target_mid], normal_mid)


func _append_quad(groups: Dictionary, material: Material, points: Array[Vector3], uvs_in: Array[Vector2], normal: Vector3) -> void:
	var key := material.get_instance_id()
	if not groups.has(key):
		groups[key] = {"material": material, "vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}
	var data: Dictionary = groups[key]
	var vertices: PackedVector3Array = data.vertices
	var normals: PackedVector3Array = data.normals
	var uvs: PackedVector2Array = data.uvs
	var indices: PackedInt32Array = data.indices
	var start := vertices.size()
	var world_to_local := global_transform.affine_inverse()
	for i in points.size():
		vertices.append(world_to_local * points[i])
		normals.append((world_to_local.basis * -normal).normalized())
		uvs.append(uvs_in[i])
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	data.vertices = vertices; data.normals = normals; data.uvs = uvs; data.indices = indices
	groups[key] = data


func _tear_depth(segment: float, segment_count: float, phase: float) -> float:
	var t := segment / segment_count
	var corner_depth := .09 if t < .09 or t > .91 else 0.0
	return clampf(.20 + .30 * (.5 + .5 * sin(segment * 2.07 + phase * 1.43)) + corner_depth, .20, .60)


func _emit_ripped_meshes(groups: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	for key in groups:
		var data: Dictionary = groups[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_TEX_UV] = data.uvs
		arrays[Mesh.ARRAY_INDEX] = data.indices
		var surface_index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface_index, data.material)
	if mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = "RaggedCanopyEdge"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _add_box(name: String, position: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = to_local(position)
	add_child(instance)
	return instance


func _build_catwalk_joints() -> void:
	if not is_instance_valid(late):
		return
	var y: float = late.ROOF_FLOOR
	var support_z: float = late.TRAMPOLINE.z
	var plates := _material(METAL_COLOR, .3)
	var dark := _material(METAL_DARK, .22)
	# The two posts at the ends of the wire get collars and foot plates. No
	# crossbar: the wire runs open, and the trampoline needs a clear shot up
	# through the tear in the canvas.
	var xs := [-8.0, 7.7]
	for x in xs:
		_add_box("CatwalkSupportFoot", Vector3(x, y + .06, support_z), Vector3(.34, .12, .34), plates)
		_add_box("CatwalkSupportCollar", Vector3(x, y + 2.84, support_z), Vector3(.34, .12, .34), plates)
		for bolt_x in [-.11, .11]:
			_add_box("CatwalkFootRivet", Vector3(x + bolt_x, y + .126, support_z), Vector3(.035, .012, .035), dark)


