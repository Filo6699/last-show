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
	# The three existing ceiling props are now joined by a modest crossbar just
	# over head height. Small collars and foot plates show how they are fastened.
	var xs := [-8.0, -1.0, 6.0]
	for x in xs:
		_add_box("CatwalkSupportFoot", Vector3(x, y + .06, support_z), Vector3(.34, .12, .34), plates)
		_add_box("CatwalkSupportCollar", Vector3(x, y + 2.84, support_z), Vector3(.34, .12, .34), plates)
		# The imported/generated suspension rod is thin at player-eye distance.
		# A sleeve makes its connection through the crossbeam visibly continuous.
		_add_box("CatwalkSuspensionSleeve",Vector3(x,y+2.95,support_z),Vector3(.10,.55,.10),plates)
		for bolt_x in [-.11, .11]:
			_add_box("CatwalkFootRivet", Vector3(x + bolt_x, y + .126, support_z), Vector3(.035, .012, .035), dark)
	for i in 2:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		_add_box("CatwalkCrossbeam", Vector3((x0 + x1) * .5, y + 2.78, support_z), Vector3(x1 - x0, .12, .14), dark)
		for x in [x0, x1]:
			_add_box("CatwalkBeamBracket", Vector3(x, y + 2.77, support_z), Vector3(.4, .2, .26), plates)
	# A pair of short diagonal knees beneath the crossbar make the joint legible.
	for x in [xs[0], xs[2]]:
		var sign := 1.0 if x == xs[0] else -1.0
		_add_box("CatwalkKneeBrace", Vector3(x + sign * .35, y + 2.55, support_z), Vector3(.72, .09, .10), dark).rotation.z = sign * -.42
