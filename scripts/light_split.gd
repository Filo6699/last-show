extends RefCounted
## Splits the few huge meshes (ground, tent canvas, ring floors, gallery
## foundation) into square tiles. The Compatibility renderer gives each object
## the lights whose bounds touch it, up to max_lights_per_object, and every pixel
## of that object loops over all of them. A 200 m ground plane touches 66 lights,
## so each of its pixels paid for 24, most of them lamps at the far end of the
## arena. A tile only gets the lamps that actually reach it.
##
## Geometry, materials and transforms stay the same: the original node keeps its
## place, name, collision and story hooks, and only its drawn mesh moves into
## child tiles. Large triangles are bisected first so a two-triangle plane can be
## tiled at all; attributes are interpolated linearly, which is exact for the
## flat or gently curved surfaces this touches.

const CELL := 12.0
# Meshes smaller than this across (metres, horizontal) are left alone.
const MIN_SPAN := 26.0
const MAX_EDGE := 12.0

static func split_world(root: Node, cell := CELL, min_span := MIN_SPAN) -> Array:
	var done: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not candidate(mi, min_span): continue
		var tiles := split(mi, cell)
		if tiles > 1: done.append([mi, tiles])
	return done

static func candidate(mi: MeshInstance3D, min_span := MIN_SPAN) -> bool:
	if not mi.visible or mi.layers == 0 or mi.mesh == null or mi.skeleton != NodePath("") and mi.get_node_or_null(mi.skeleton) is Skeleton3D: return false
	if mi.has_meta("light_split") or mi.get_parent().has_meta("light_split"): return false
	if mi.mesh is ArrayMesh and mi.mesh.get_blend_shape_count() > 0: return false
	var box := mi.global_transform * mi.get_aabb()
	if maxf(box.size.x, box.size.z) < min_span: return false
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m is BaseMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
		if m is ShaderMaterial and m.shader and m.shader.code.contains("ALPHA"): return false
	return true

# Returns the number of tiles made (0 if the mesh was left as it was).
static func split(mi: MeshInstance3D, cell: float) -> int:
	var mesh := mi.mesh
	var to_world := mi.global_transform
	var box := to_world * mi.get_aabb()
	# Very large meshes (the 200 m ground) get coarser tiles: at most 8 per side.
	cell = maxf(cell, maxf(box.size.x, box.size.z) / 8.0)
	# cell key -> {surface: [items]}; an item is a source triangle's first index
	# (copied as is) or three interpolated vertices from a bisected triangle.
	var cells := {}
	var surfaces := mesh.get_surface_count()
	var all_arrays: Array = []
	for s in surfaces:
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: return 0
		var arrays := mesh.surface_get_arrays(s)
		all_arrays.append(arrays)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx == null or idx.is_empty():
			idx = PackedInt32Array(range(pos.size()))
			arrays[Mesh.ARRAY_INDEX] = idx
		var cache := {}
		for k in range(0, idx.size() - 2, 3):
			var a := pos[idx[k]]; var b := pos[idx[k + 1]]; var c := pos[idx[k + 2]]
			var items: Array = []
			if maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) <= MAX_EDGE:
				items.append(k)
			else:
				var tri: Array = []
				for j in 3:
					var i: int = idx[k + j]
					if not cache.has(i): cache[i] = vert(arrays, i)
					tri.append(cache[i])
				bisect(tri, items, 0)
			for item in items:
				var centre: Vector3
				if item is int: centre = to_world * ((a + b + c) / 3.0)
				else: centre = to_world * ((item[0].v + item[1].v + item[2].v) / 3.0)
				var key := Vector2i(floori(centre.x / cell), floori(centre.z / cell))
				if not cells.has(key): cells[key] = {}
				if not cells[key].has(s): cells[key][s] = []
				cells[key][s].append(item)
	if cells.size() < 2: return 0
	for key in cells:
		var tile_mesh := ArrayMesh.new()
		var surface_map: Array = []
		for s in surfaces:
			if not cells[key].has(s): continue
			tile_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, build(cells[key][s], all_arrays[s]))
			tile_mesh.surface_set_material(tile_mesh.get_surface_count() - 1, mesh.surface_get_material(s))
			surface_map.append(s)
		var tile := MeshInstance3D.new()
		tile.name = "LightTile_%d_%d" % [key.x, key.y]
		tile.mesh = tile_mesh
		tile.material_override = mi.material_override
		tile.material_overlay = mi.material_overlay
		for i in surface_map.size():
			var o := mi.get_surface_override_material(surface_map[i])
			if o: tile.set_surface_override_material(i, o)
		tile.cast_shadow = mi.cast_shadow
		tile.layers = mi.layers
		tile.gi_mode = mi.gi_mode
		tile.visibility_range_begin = mi.visibility_range_begin
		tile.visibility_range_end = mi.visibility_range_end
		tile.extra_cull_margin = mi.extra_cull_margin
		tile.sorting_offset = mi.sorting_offset
		tile.set_meta("light_split", true)
		mi.add_child(tile)
	# The original stays in the tree (collision, story code, outline lookups find
	# it by name) but draws nothing itself.
	# Layer 0 keeps the original out of every camera and shadow pass while its
	# mesh, bounds and materials stay readable to the rest of the game.
	mi.set_meta("light_split", mi.layers)
	mi.layers = 0
	return cells.size()

static func undo(mi: MeshInstance3D) -> void:
	if not mi.has_meta("light_split"): return
	for child in mi.get_children():
		if child.has_meta("light_split"): child.free()
	mi.layers = mi.get_meta("light_split")
	mi.remove_meta("light_split")

class Vert:
	var v: Vector3
	var n: Vector3
	var t: Plane
	var c: Color
	var uv: Vector2
	var uv2: Vector2
	func lerp_to(o: Vert, f: float) -> Vert:
		var r := Vert.new()
		r.v = v.lerp(o.v, f)
		r.n = n.lerp(o.n, f).normalized() if n != Vector3.ZERO else Vector3.ZERO
		var tv := Vector3(t.x, t.y, t.z).lerp(Vector3(o.t.x, o.t.y, o.t.z), f)
		r.t = Plane(tv.normalized() if tv != Vector3.ZERO else tv, t.d)
		r.c = c.lerp(o.c, f)
		r.uv = uv.lerp(o.uv, f)
		r.uv2 = uv2.lerp(o.uv2, f)
		return r

static func vert(arrays: Array, i: int) -> Vert:
	var r := Vert.new()
	r.v = arrays[Mesh.ARRAY_VERTEX][i]
	if arrays[Mesh.ARRAY_NORMAL] != null: r.n = arrays[Mesh.ARRAY_NORMAL][i]
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		r.t = Plane(tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2], tg[i * 4 + 3])
	if arrays[Mesh.ARRAY_COLOR] != null: r.c = arrays[Mesh.ARRAY_COLOR][i]
	if arrays[Mesh.ARRAY_TEX_UV] != null: r.uv = arrays[Mesh.ARRAY_TEX_UV][i]
	if arrays[Mesh.ARRAY_TEX_UV2] != null: r.uv2 = arrays[Mesh.ARRAY_TEX_UV2][i]
	return r

static func triangles(arrays: Array) -> Array:
	var out: Array = []
	var idx = arrays[Mesh.ARRAY_INDEX]
	var count: int = idx.size() if idx != null else arrays[Mesh.ARRAY_VERTEX].size()
	var cache := {}
	for k in range(0, count - 2, 3):
		var tri: Array = []
		for j in 3:
			var i: int = idx[k + j] if idx != null else k + j
			if not cache.has(i): cache[i] = vert(arrays, i)
			tri.append(cache[i])
		bisect(tri, out, 0)
	return out

# Splits along the longest edge until every edge is at most MAX_EDGE.
static func bisect(tri: Array, out: Array, depth: int) -> void:
	var e := [tri[0].v.distance_to(tri[1].v), tri[1].v.distance_to(tri[2].v), tri[2].v.distance_to(tri[0].v)]
	var longest := 0
	if e[1] > e[longest]: longest = 1
	if e[2] > e[longest]: longest = 2
	if e[longest] <= MAX_EDGE or depth > 14:
		out.append(tri); return
	var a: Vert = tri[longest]; var b: Vert = tri[(longest + 1) % 3]; var c: Vert = tri[(longest + 2) % 3]
	var m := a.lerp_to(b, .5)
	bisect([a, m, c], out, depth + 1)
	bisect([m, b, c], out, depth + 1)

static func build(items: Array, source: Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var src_pos: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var src_idx: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var src_nor = source[Mesh.ARRAY_NORMAL]; var src_tan = source[Mesh.ARRAY_TANGENT]
	var src_col = source[Mesh.ARRAY_COLOR]; var src_uv = source[Mesh.ARRAY_TEX_UV]; var src_uv2 = source[Mesh.ARRAY_TEX_UV2]
	var pos := PackedVector3Array(); var nor := PackedVector3Array(); var tan := PackedFloat32Array()
	var col := PackedColorArray(); var uv := PackedVector2Array(); var uv2 := PackedVector2Array()
	var index := PackedInt32Array()
	var by_source := {}
	var by_vert := {}
	for item in items:
		if item is int:
			for j in 3:
				var i: int = src_idx[item + j]
				var id: int = by_source.get(i, -1)
				if id < 0:
					id = pos.size(); by_source[i] = id
					pos.append(src_pos[i])
					nor.append(src_nor[i] if src_nor != null else Vector3.ZERO)
					if src_tan != null:
						for q in 4: tan.append(src_tan[i * 4 + q])
					else:
						for q in 4: tan.append(0.0)
					col.append(src_col[i] if src_col != null else Color.WHITE)
					uv.append(src_uv[i] if src_uv != null else Vector2.ZERO)
					uv2.append(src_uv2[i] if src_uv2 != null else Vector2.ZERO)
				index.append(id)
		else:
			for v in item:
				var id: int = by_vert.get(v, -1)
				if id < 0:
					id = pos.size(); by_vert[v] = id
					pos.append(v.v); nor.append(v.n)
					tan.append(v.t.x); tan.append(v.t.y); tan.append(v.t.z); tan.append(v.t.d)
					col.append(v.c); uv.append(v.uv); uv2.append(v.uv2)
				index.append(id)
	arrays[Mesh.ARRAY_VERTEX] = pos
	if src_nor != null: arrays[Mesh.ARRAY_NORMAL] = nor
	if src_tan != null: arrays[Mesh.ARRAY_TANGENT] = tan
	if src_col != null: arrays[Mesh.ARRAY_COLOR] = col
	if src_uv != null: arrays[Mesh.ARRAY_TEX_UV] = uv
	if src_uv2 != null: arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays

# Phones: lamps without shadows fade out between FADE_BEGIN and FADE_BEGIN +
# FADE_LENGTH metres from the camera and are skipped beyond. Their pools of light
# that far away cover a few pixels under the haze; screenshots of all ten
# locations match the unfaded ones within animation noise.
const FADE_BEGIN := 40.0
const FADE_LENGTH := 10.0

static func fade_far_lights(root: Node) -> Array:
	var touched: Array = []
	for node in root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light is DirectionalLight3D or light.shadow_enabled or light.distance_fade_enabled: continue
		light.distance_fade_enabled = true
		light.distance_fade_begin = FADE_BEGIN
		light.distance_fade_length = FADE_LENGTH
		touched.append(light)
	return touched
