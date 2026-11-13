extends Node
## Skips render work that never reaches the screen. Nothing visible changes:
## - the tent canvas occludes whatever stands behind it;
## - characters nobody can see (directly or in the mirror) hold their idle pose,
##   so their skeletons stop invalidating cached shadow maps every frame;
## - while a menu or opaque overlay covers the view, the 3D scene is not drawn;
## - the main tent wall hides the dressing tent, clinic and house behind it
##   (zone_culling.gd: Godot's occlusion buffer is too coarse at 50 m);
## - only the few shadowed keys nearest the camera render shadow maps.
var game
# The Compatibility renderer draws every object again for each shadowed light
# that reaches it, on top of the shadow map itself. Seven always-on shadowed
# keys tripled the opening's draw calls; the nearest ones carry the look.
var shadow_lights: Array[Light3D] = []
var shadow_clock := 0.0
const SHADOW_INTERVAL := .25
# Visibility bounds per actor, grown so a nearby shadow keeps its owner moving.
const ACTOR_BOUNDS := AABB(Vector3(-2.2, -2.2, -2.2), Vector3(4.4, 5.4, 4.4))

func setup(owner_game) -> void:
	game = owner_game
	# build_occluders() culled the tent roof when looking up, leaving a white screen.
	for id in game.actors: watch_actor(game.actors[id])
	build_room_occluders()
	var zones := preload("res://scripts/zone_culling.gd").new()
	zones.name = "ZoneCulling"; add_child(zones); zones.setup(game)
	for light in game.find_children("*", "Light3D", true, false):
		if light.shadow_enabled and not light is DirectionalLight3D: shadow_lights.append(light)
	update_shadows()
	if is_instance_valid(game.graphics): game.graphics.changed.connect(update_shadows)

# The service corridor and the clinic are closed boxes inside the big tent. From
# there the ring is only visible through the narrow corridor mouth, yet without
# occluders the whole arena (thousands of draw calls) was drawn behind the walls.
# Each occluder sits inside an existing wall or ceiling, so it hides nothing
# that the wall itself would not.
func build_room_occluders() -> void:
	var x: float = game.layout.SERVICE_X
	var walls := [
		# Vestibule and corridor side walls, backstage wall to clinic wall.
		[Vector3(x - 1.41, 1.6, 46.2), Vector3(.05, 3.1, 15.6)],
		[Vector3(x + 1.41, 1.6, 46.2), Vector3(.05, 3.1, 15.6)],
		# Corridor and vestibule ceiling.
		[Vector3(x, 3.12, 46.2), Vector3(2.9, .04, 15.6)],
		# Clinic: two front pieces beside the doorway, lintel, back and sides.
		[Vector3(-22.6, 1.65, 53.98), Vector3(2.0, 3.3, .05)],
		[Vector3(-17.65, 1.65, 53.98), Vector3(1.9, 3.3, .05)],
		[Vector3(x, 3.2, 53.98), Vector3(2.8, .4, .05)],
		[Vector3(-20.15, 1.65, 60.0), Vector3(7.0, 3.3, .05)],
		[Vector3(-23.6, 1.65, 57.0), Vector3(.05, 3.3, 6.1)],
		[Vector3(-16.6, 1.65, 57.0), Vector3(.05, 3.3, 6.1)],
		[Vector3(-20.15, 3.42, 57.0), Vector3(7.0, .04, 6.1)],
	]
	var holder := Node3D.new()
	holder.name = "RoomOccluders"
	game.world.add_child(holder)
	for entry in walls:
		var shape := BoxOccluder3D.new()
		shape.size = entry[1]
		var occluder := OccluderInstance3D.new()
		occluder.occluder = shape
		occluder.position = entry[0]
		holder.add_child(occluder)
	# Backstage room: the corridor opens into it, the ring lies behind its
	# curtain wall. Its walls and ceiling hide the arena except through the door.
	var room: Node = game.location.get_node_or_null("Backstage") if is_instance_valid(game.location) else null
	if room == null: return
	var height: float = room.HEIGHT
	var ends: Array = room.front_line()
	var along: Vector3 = (ends[1] - ends[0]).normalized()
	var half: float = room.DOOR_WIDTH * .5
	var door: Vector3 = room.door_center
	var service_a := Vector3(x - 1.4, 0, room.BACK_Z)
	var service_b := Vector3(x + 1.4, 0, room.BACK_Z)
	var panels := [
		[ends[0], door - along * half, 0.0, height],
		[door + along * half, ends[1], 0.0, height],
		[door - along * half, door + along * half, room.DOOR_HEIGHT + .05, height],
		[Vector3(room.EAST_X, 0, room.front_z(room.EAST_X) - .2), Vector3(room.EAST_X, 0, room.BACK_Z + .1), 0.0, height],
		[Vector3(room.WEST_X - .1, 0, room.BACK_Z), service_a, 0.0, height],
		[service_b, Vector3(room.EAST_X + .1, 0, room.BACK_Z), 0.0, height],
		[service_a, service_b, 3.05, height],
	]
	for entry in panels:
		var a: Vector3 = entry[0]
		var b: Vector3 = entry[1]
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		var shape := BoxOccluder3D.new()
		shape.size = Vector3(flat.length(), entry[3] - entry[2] - .05, .04)
		var occluder := OccluderInstance3D.new()
		occluder.occluder = shape
		occluder.position = Vector3((a.x + b.x) * .5, (entry[2] + entry[3]) * .5, (a.z + b.z) * .5)
		occluder.rotation.y = atan2(-flat.z, flat.x)
		holder.add_child(occluder)
	var corners := [Vector3(room.WEST_X, 0, room.BACK_Z), Vector3(room.WEST_X, 0, room.WEST_X / tan(deg_to_rad(room.NW_EDGE))), ends[0], Vector3(room.EAST_X, 0, room.front_z(room.EAST_X)), Vector3(room.EAST_X, 0, room.BACK_Z)]
	var points := PackedVector3Array()
	for corner in corners: points.append(corner + Vector3(0, height + .05, 0))
	var indices := PackedInt32Array()
	for i in range(1, points.size() - 1): indices.append_array([0, i + 1, i, 0, i, i + 1])
	var lid := ArrayOccluder3D.new()
	lid.set_arrays(points, indices)
	var ceiling := OccluderInstance3D.new()
	ceiling.occluder = lid
	holder.add_child(ceiling)

# Shadows follow the camera: the keys whose reach covers it, nearest first, keep
# their shadow maps; distant ones light without them. A small bonus for lights
# already shadowed stops two equally near keys from flickering between frames.
func update_shadows() -> void:
	var budget: int = game.graphics.shadow_light_count() if is_instance_valid(game.graphics) else 2
	var eye: Vector3 = game.player.camera.global_position
	var ranked: Array = []
	for light in shadow_lights:
		if not is_instance_valid(light) or not light.is_visible_in_tree() or light.light_energy < .02: continue
		var reach: float = light.spot_range if light is SpotLight3D else light.omni_range
		var distance := eye.distance_to(light.global_position)
		if distance > reach * 1.15: continue
		ranked.append([distance / reach - (.1 if light.shadow_enabled else 0.0), light])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	var chosen := {}
	for index in mini(budget, ranked.size()): chosen[ranked[index][1]] = true
	for light in shadow_lights:
		if is_instance_valid(light): light.shadow_enabled = chosen.has(light)

func build_occluders() -> void:
	# Occluders reuse the exact canvas triangles, so they hide nothing that the
	# canvas itself would not. As children of the mesh they share its visibility.
	for source in game.model.find_children("*", "MeshInstance3D", true, false):
		var name := String(source.name)
		if not source.mesh or not (name.contains("Tent") or name.contains("Шатер")): continue
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		for surface in source.mesh.get_surface_count():
			if not opaque(source.get_active_material(surface)): continue
			var arrays: Array = source.mesh.surface_get_arrays(surface)
			var base: int = vertices.size()
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertices.append_array(points)
			var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if surface_indices.is_empty():
				for index in points.size(): indices.append(base + index)
			else:
				for index in surface_indices: indices.append(base + index)
		if indices.is_empty(): continue
		var shape := ArrayOccluder3D.new()
		shape.set_arrays(vertices, indices)
		var occluder := OccluderInstance3D.new()
		occluder.name = "CanvasOccluder"
		occluder.occluder = shape
		source.add_child(occluder)

func opaque(material: Material) -> bool:
	if material is BaseMaterial3D:
		return material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	if material is ShaderMaterial and material.shader:
		var code: String = material.shader.code
		return not (code.contains("ALPHA") or code.contains("discard"))
	return material == null

func watch_actor(actor: Node3D) -> void:
	var animators: Array[AnimationMixer] = []
	for animator in actor.find_children("*", "AnimationMixer", true, false): animators.append(animator)
	var attention: Node = actor.get_node_or_null("NewsAttention")
	if animators.is_empty() and attention == null: return
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = "AnimationCulling"
	notifier.aabb = ACTOR_BOUNDS
	actor.add_child(notifier)
	notifier.screen_entered.connect(set_actor_live.bind(animators, attention, true))
	notifier.screen_exited.connect(set_actor_live.bind(animators, attention, false))
	# The notifier only reports actors once they reach a camera. Start everyone
	# posed on their first idle frame and resume them as soon as they are seen.
	for animator in animators: animator.advance(0)
	set_actor_live(animators, attention, false)

func set_actor_live(animators: Array[AnimationMixer], attention: Node, live: bool) -> void:
	for animator in animators: animator.active = live
	# Attention keeps its timers and voice cue; only the pose waits for a viewer.
	if attention: attention.on_screen = live

# Lights are not occlusion culled. From the corridor or the clinic every arena
# spot in the view direction still rendered its shadow map and lit hidden
# objects behind the walls, so those rooms switch off lights outside them.
const ENCLOSED_ROOMS := ["service", "clinic"]
const ENCLOSED_LIGHTS := AABB(Vector3(-25, -1, 24), Vector3(14, 10, 38))
var gated_lights: Array[Light3D] = []
var gate_wait := 0.0

func update_light_gate(delta: float) -> void:
	gate_wait -= delta
	if gate_wait > 0: return
	gate_wait = .2
	var enclosed: bool = game.room_at(game.player.global_position) in ENCLOSED_ROOMS
	if enclosed == not gated_lights.is_empty(): return
	if not enclosed:
		for light in gated_lights:
			if is_instance_valid(light): light.visible = true
		gated_lights.clear()
		return
	for light in game.world.find_children("*", "Light3D", true, false):
		if not light.visible or ENCLOSED_LIGHTS.has_point(light.global_position): continue
		light.visible = false
		gated_lights.append(light)

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	update_light_gate(delta)
	shadow_clock += delta
	if shadow_clock >= SHADOW_INTERVAL:
		shadow_clock = 0.0
		update_shadows()
	var hud = game.hud
	# Menus, story cards and a fully black fade cover the world so heavily that
	# drawing it only costs frames; the backdrop shows the same near-black.
	get_viewport().disable_3d = hud.menu.visible or hud.story_backdrop.visible or (hud.fade.visible and hud.fade.modulate.a >= .999)
