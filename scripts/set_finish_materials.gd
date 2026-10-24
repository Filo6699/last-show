extends RefCounted
## Shared material finishes for added set dressing. Source textures and imported
## materials remain intact; only their physical roughness/metal response is tuned.

static var _normal_maps: Dictionary = {}

const KIND_IDS := {
	"paint": 0,
	"wood": 1,
	"cloth": 2,
	"metal": 3,
	"leather": 4,
}

static func make_surface(
	color: Color,
	kind: StringName = &"paint",
	metal: float = -1.0,
	rough: float = -1.0,
	glow: float = 0.0,
	source: StandardMaterial3D = null
) -> StandardMaterial3D:
	var kind_name := String(kind).to_lower()
	if not KIND_IDS.has(kind_name):
		kind_name = "paint"
	var resolved_metal := metal
	var resolved_rough := rough
	var albedo_texture: Texture2D
	if source != null:
		if resolved_metal < 0.0:
			resolved_metal = source.metallic
		if resolved_rough < 0.0:
			resolved_rough = source.roughness
		if source.albedo_texture != null:
			albedo_texture = source.albedo_texture
			color *= source.albedo_color
	if resolved_metal < 0.0:
		resolved_metal = 0.65 if kind_name == "metal" else 0.0
	if resolved_rough < 0.0:
		match kind_name:
			"wood": resolved_rough = 0.82
			"cloth": resolved_rough = 0.97
			"metal": resolved_rough = 0.46
			"leather": resolved_rough = 0.68
			_: resolved_rough = 0.86
	var material := source.duplicate() as StandardMaterial3D if source != null else StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = clampf(resolved_metal, 0.0, 1.0)
	material.roughness = clampf(resolved_rough, 0.18, 1.0)
	if albedo_texture != null:
		material.albedo_texture = albedo_texture
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	if kind_name in ["wood", "cloth", "leather"]:
		material.normal_enabled = true
		material.normal_texture = _normal_map(kind_name)
		material.normal_scale = 0.035 if kind_name == "wood" else (0.02 if kind_name == "cloth" else 0.015)
	return material


static func _normal_map(kind: String) -> Texture2D:
	if _normal_maps.has(kind):
		return _normal_maps[kind]
	# A tiny seamless normal map is generated from broad, category-specific
	# height functions. Wood gets lengthwise grain, cloth a faint woven relief,
	# and leather a broad soft pebble. Low cycle counts avoid shimmering on mobile.
	const RESOLUTION := 128
	var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
	var step := 1.0 / float(RESOLUTION)
	for y in RESOLUTION:
		for x in RESOLUTION:
			var uv := Vector2(float(x) / RESOLUTION, float(y) / RESOLUTION)
			var dx := (_height(kind, uv + Vector2(step, 0.0)) - _height(kind, uv - Vector2(step, 0.0))) / (2.0 * step)
			var dy := (_height(kind, uv + Vector2(0.0, step)) - _height(kind, uv - Vector2(0.0, step))) / (2.0 * step)
			var normal := Vector3(-dx * 1.7, -dy * 1.7, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_normal_maps[kind] = texture
	return texture


static func _height(kind: String, uv: Vector2) -> float:
	if kind == "wood":
		var grain := sin(uv.y * TAU * 3.0 + sin(uv.x * TAU) * 0.8) * 0.028
		grain += sin(uv.y * TAU * 7.0 + sin(uv.x * TAU * 0.5) * 0.4) * 0.006
		return grain
	if kind == "cloth":
		var weave := sin(uv.x * TAU * 4.0) * sin(uv.y * TAU * 4.0) * 0.009
		var fold := sin((uv.x + uv.y * 0.36) * TAU * 2.0) * 0.012
		return weave + fold
	var pebble := sin(uv.x * TAU * 3.0 + sin(uv.y * TAU * 2.0)) * 0.012
	return pebble + sin(uv.y * TAU * 2.0 + sin(uv.x * TAU)) * 0.008


static func apply_authored(root: Node) -> Dictionary:
	## Retune clearly named imported wood, cloth, leather, and metal surfaces.
	## Keeps their original StandardMaterial3D, albedo textures and normal maps.
	## Active ShaderMaterials (canvas, mirrors, screens) are deliberately skipped.
	var counts := {"wood": 0, "cloth": 0, "leather": 0, "metal": 0}
	var tuned_materials: Dictionary = {}
	if root == null:
		return counts
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if _is_display_surface(node):
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var active := mesh_instance.get_active_material(surface)
			if active is ShaderMaterial or not active is StandardMaterial3D:
				continue
			var material := active as StandardMaterial3D
			# Keep transparency, cut-outs and emissive art exactly as authored.
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.emission_enabled:
				continue
			var kind := _kind_from_name(String(material.resource_name))
			if kind.is_empty():
				continue
			if String(material.resource_name).to_lower() == "wood_planks":
				continue
			var material_id := material.get_instance_id()
			var tuned: StandardMaterial3D
			if tuned_materials.has(material_id):
				tuned = tuned_materials[material_id]
			else:
				tuned = material.duplicate() as StandardMaterial3D
				tuned.resource_name = material.resource_name
				match kind:
					"wood":
						tuned.metallic = minf(tuned.metallic, 0.04)
						tuned.roughness = maxf(tuned.roughness, 0.78)
					"cloth":
						tuned.metallic = 0.0
						tuned.roughness = maxf(tuned.roughness, 0.94)
					"leather":
						tuned.metallic = minf(tuned.metallic, 0.03)
						tuned.roughness = clampf(maxf(tuned.roughness, 0.63), 0.63, 0.82)
					"metal":
						tuned.metallic = maxf(tuned.metallic, 0.52)
						tuned.roughness = clampf(tuned.roughness, 0.34, 0.62)
				tuned_materials[material_id] = tuned
			mesh_instance.set_surface_override_material(surface, tuned)
			counts[kind] += 1
	return counts


static func _kind_from_name(material_name: String) -> String:
	var name := material_name.to_lower()
	if "walnut" in name or "wood" in name or "plank" in name:
		return "wood"
	if "leather" in name or "satin" in name:
		return "leather"
	if "canvas" in name or "cloth" in name or "fabric" in name:
		return "cloth"
	if "brass" in name or "metal" in name or "plate" in name or name == "bar":
		return "metal"
	return ""


static func _is_display_surface(node: MeshInstance3D) -> bool:
	var node_name := node.name.to_lower()
	if "mirror" in node_name or "screen" in node_name or "display" in node_name:
		return true
	for surface in node.mesh.get_surface_count() if node.mesh != null else 0:
		var material := node.get_active_material(surface)
		if material is ShaderMaterial:
			return true
		if material != null:
			var name := material.resource_name.to_lower()
			if "mirror" in name or "screen" in name or "display" in name:
				return true
	return false
