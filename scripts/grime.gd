extends Node3D
## Dirt pass: stains, spatter and dropped tickets on the floors, rust drips on
## the walls, cobwebs under ceilings. Placement uses raycasts against the built
## level, so it follows whatever the layout is. One MultiMesh per texture keeps
## it to a handful of draw calls. Fixed seed: the mess is the same every run.
const AREA := Rect2(-30, -30, 60, 92)
# [area, floor marks, wall marks]: tight rooms get far more per square metre
# than the open arena so the corridor and clinic read as neglected.
const REGIONS := [
	[Rect2(-21.4, 38, 2.8, 16), 22, 13],
	[Rect2(-23.5, 54, 6.8, 6), 13, 7],
	[Rect2(-23, -23, 46, 46), 210, 20],
	[Rect2(-30, -30, 60, 14), 45, 25],
	[Rect2(-30, -30, 60, 92), 30, 15],
]

var game
var rng := RandomNumberGenerator.new()
var sets := {}

func setup(owner_game) -> void:
	game = owner_game
	name = "Grime"
	rng.seed = 1931
	place.call_deferred()

func layer_for(texture: String, size: Vector2) -> Array:
	if not sets.has(texture):
		sets[texture] = {"size": size, "items": []}
	return sets[texture]["items"]

func space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state

# Only world geometry (layer 1) that is actually drawn counts as a surface.
# Invisible blockers, interaction zones and the cast all have colliders too;
# marks stuck to those hang in the air or ride on a character.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	var hit := space().intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	return hit if hit.is_empty() or drawn_surface(hit.collider) else {}

func drawn_surface(collider: Object) -> bool:
	if not collider is StaticBody3D: return false
	var body: StaticBody3D = collider
	if "interaction_id" in body: return false
	for actor in game.actors.values():
		if actor == body or actor.is_ancestor_of(body): return false
	if body.has_meta("source_mesh"): return true
	var parent := body.get_parent()
	return parent is MeshInstance3D and parent.is_visible_in_tree()

# The wall must still be there at the given point, a hand's width away at most.
func wall_at(point: Vector3, normal: Vector3, collider: Object) -> bool:
	var hit := ray(point + normal * .12, point - normal * .12)
	return not hit.is_empty() and hit.collider == collider and hit.normal.dot(normal) > .9

func indoor(p: Vector3) -> bool:
	return not String(game.room_at(p)).is_empty()

func place() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(game): return
	for region in REGIONS:
		scatter_floor(region[0], region[1])
		scatter_walls(region[0], region[2])
	build()

func scatter_floor(area: Rect2, count: int) -> void:
	var floors := 0
	var tries := 0
	while floors < count and tries < count * 8:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 2.6, rng.randf_range(area.position.y, area.end.y))
		if not indoor(p): continue
		var hit := ray(p, p + Vector3.DOWN * 3.2)
		if hit.is_empty() or hit.normal.y < .9 or hit.position.y > .9: continue
		var roll := rng.randf()
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI / 2)
		# The arena's ring cloth (r 14.5) sits 7 cm above its collision plane;
		# everywhere else, and on top of props, the mark lies on the surface.
		var on_ring: bool = Vector2(p.x, p.z - .1).length() < 14.3 and hit.position.y < .03
		var lift := .085 if on_ring else .015
		var at: Vector3 = hit.position + Vector3.UP * (lift + rng.randf() * .008)
		if roll < .5: layer_for("stain", Vector2(1, 1)).append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(.6, 2.2)), at))
		elif roll < .75: layer_for("spatter", Vector2(1, 1)).append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(.5, 1.4)), at))
		elif roll < .82: layer_for("blood", Vector2(1, 1)).append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(.3, .8)), at))
		else: layer_for("paper", Vector2(.22, .22)).append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(.7, 1.2)), at + Vector3.UP * .004))
		floors += 1

func scatter_walls(area: Rect2, count: int) -> void:
	var walls := 0
	var tries := 0
	while walls < count and tries < count * 10:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 1.4, rng.randf_range(area.position.y, area.end.y))
		if not indoor(p): continue
		var angle := rng.randf() * TAU
		var hit := ray(p, p + Vector3(cos(angle), 0, sin(angle)) * 4.0)
		if hit.is_empty() or absf(hit.normal.y) > .15: continue
		var normal: Vector3 = hit.normal
		var right := Vector3.UP.cross(normal).normalized()
		var basis := Basis(right, Vector3.UP, normal)
		# Both drips and cobwebs hang from a real ceiling line; without one a
		# drip would start mid-wall.
		var above := ray(hit.position + normal * .1, hit.position + normal * .1 + Vector3.UP * 3.5)
		if above.is_empty(): continue
		if rng.randf() < .55:
			# Rust and damp running down from the top of the wall.
			var top: float = above.position.y - .05
			var height := minf(top - .05, rng.randf_range(1.2, 2.6))
			if height < .4: continue
			var at: Vector3 = Vector3(hit.position.x, top - height * .5, hit.position.z) + normal * .01
			var width := rng.randf_range(.6, 1.4)
			var half_width := width * .5
			if not (wall_at(Vector3(hit.position.x, top - height, hit.position.z), normal, hit.collider) \
				and wall_at(Vector3(hit.position.x, top, hit.position.z) + right * half_width, normal, hit.collider) \
				and wall_at(Vector3(hit.position.x, top, hit.position.z) - right * half_width, normal, hit.collider)): continue
			layer_for("drips", Vector2(1, 2)).append(Transform3D(basis.scaled(Vector3(width, height / 2.0, 1)), at))
		else:
			# Cobweb hanging from the ceiling line, anchored at its top corner.
			var size := rng.randf_range(.5, 1.1)
			var flip := 1.0 if rng.randf() < .5 else -1.0
			var at: Vector3 = Vector3(hit.position.x, above.position.y - size * .5, hit.position.z) + normal * .02
			if not wall_at(Vector3(hit.position.x, above.position.y - size, hit.position.z), normal, hit.collider): continue
			layer_for("cobweb", Vector2(1, 1)).append(Transform3D(basis.scaled(Vector3(size * flip, size, 1)), at))
		walls += 1

func build() -> void:
	for texture in sets:
		var items: Array = sets[texture]["items"]
		if items.is_empty(): continue
		var quad := QuadMesh.new()
		quad.size = sets[texture]["size"]
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/textures/grime/%s.png" % texture)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 1.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if texture == "cobweb":
			material.albedo_color = Color(1, 1, 1, .55)
			material.uv1_scale = Vector3(1, 1, 1)
		quad.material = material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = quad
		multimesh.instance_count = items.size()
		for i in items.size(): multimesh.set_instance_transform(i, items[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Grime_" + texture
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
