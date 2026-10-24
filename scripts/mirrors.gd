extends Node3D
## Planar reflections: shared 3D world, reflected eye, off-axis frustum.
## Layer 2 is Richard (hidden from his own camera); layer 4 is mirror glass.
var game
var avatar: Node3D
var mirrors: Array[Dictionary] = []
var skeleton: Skeleton3D
var gait := 0.0
var walk_weight := 0.0
var previous_position := Vector3.ZERO
var bone_data := {}
var active_mirror := -1
var reflection_clock := 0.0
const INTERACTION_RANGE := 1.8
var walk_axis := Vector3.RIGHT
var smile := false
var cinematic := false
var saved_rotation := Quaternion.IDENTITY
var saved_fov := 75.0
var camera_tween: Tween

func setup(owner_game: Node3D) -> void:
	game = owner_game
	avatar = load("res://assets/characters/models/richard.glb").instantiate()
	avatar.name = "RichardBody"
	add_child(avatar)
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		node.layers = 2
		if String(node.name).begins_with("Uncanny"): node.hide()
	skeleton = avatar.find_children("*", "Skeleton3D", true, false)[0]
	# Keep the authored relaxed arm pose; add motion in skeleton space.
	for animator in avatar.find_children("*", "AnimationPlayer", true, false):
		for clip in animator.get_animation_list():
			if clip != "RESET":
				animator.play(clip); animator.advance(0); animator.pause()
				break
	for i in skeleton.get_bone_count():
		bone_data[skeleton.get_bone_name(i)] = {"index":i,"pose":skeleton.get_bone_pose_rotation(i),"basis":skeleton.get_bone_global_rest(i).basis.get_rotation_quaternion()}
	previous_position = game.player.global_position
	game.player.camera.cull_mask = 1 | 4
	add_surface(game.model.find_child("Mirror surface", true, false))
	# Keep one authored story mirror. The other tables remain useful dressing
	# furniture, with their glass and oval frame removed rather than hidden behind
	# additional live reflection viewports.
	for vanity in game.layout.vanity_meshes(game.model):
		remove_vanity_mirror(vanity)
	for target in game.targets.get("mirror",[]):
		if is_instance_valid(target):target.set_meta("focus_range",INTERACTION_RANGE)

func remove_vanity_mirror(vanity: MeshInstance3D) -> void:
	var replacement := ArrayMesh.new()
	for index in vanity.mesh.get_surface_count():
		var material:Material=vanity.get_active_material(index)
		if material and material.resource_name.begins_with("Clouded_mirror"):continue
		var arrays:Array=vanity.mesh.surface_get_arrays(index)
		if material and material.resource_name.begins_with("Tarnished_brass"):
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex in vertices.size():indices.append(vertex)
			var kept:=PackedInt32Array()
			for triangle in range(0,indices.size(),3):
				var center:Vector3=(vertices[indices[triangle]]+vertices[indices[triangle+1]]+vertices[indices[triangle+2]])/3.0
				if center.y>1.10 and absf(center.x)<.45 and center.z<-.12:continue
				kept.append(indices[triangle]);kept.append(indices[triangle+1]);kept.append(indices[triangle+2])
			arrays[Mesh.ARRAY_INDEX]=kept
			if kept.is_empty():continue
		replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		replacement.surface_set_material(replacement.get_surface_count()-1,material)
	vanity.mesh=replacement
	for body in game.model.get_node("GeometryCollisions").get_children():
		if body.get_meta("source_mesh","")==String(vanity.name):
			var faces:=replacement.get_faces()
			var to_body:Transform3D=body.global_transform.affine_inverse()*vanity.global_transform
			for vertex in faces.size():faces[vertex]=to_body*faces[vertex]
			var collision:=ConcavePolygonShape3D.new();collision.set_faces(faces);collision.backface_collision=true
			for shape in body.get_children():
				if shape is CollisionShape3D:shape.shape=collision

func add_surface(surface: MeshInstance3D) -> void:
	var faces := surface.mesh.get_faces()
	var normal: Vector3 = ((surface.global_transform*faces[1])-(surface.global_transform*faces[0])).cross((surface.global_transform*faces[2])-(surface.global_transform*faces[0])).normalized()
	if normal.z < 0: normal = -normal
	var right := Vector3.UP.cross(normal).normalized()
	var up := normal.cross(right).normalized()
	var origin: Vector3 = surface.global_transform*faces[0]
	var bounds := Rect2(Vector2.ZERO,Vector2.ZERO)
	for v in faces:
		var offset: Vector3 = surface.global_transform*v-origin
		bounds = bounds.expand(Vector2(offset.dot(right),offset.dot(up)))
	var center := origin+right*bounds.get_center().x+up*bounds.get_center().y
	# Project UVs onto the glass plane while preserving the artist's curved outline.
	var mapped := ArrayMesh.new()
	for index in surface.mesh.get_surface_count():
		var arrays := surface.mesh.surface_get_arrays(index)
		var uvs := PackedVector2Array()
		for v in arrays[Mesh.ARRAY_VERTEX]:
			var offset: Vector3 = surface.global_transform*v-origin
			uvs.append(Vector2((offset.dot(right)-bounds.position.x)/bounds.size.x,1.0-(offset.dot(up)-bounds.position.y)/bounds.size.y))
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.mesh = mapped
	surface.layers = 4
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, int(160*bounds.size.y/bounds.size.x))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.positional_shadow_atlas_size = 512
	add_child(viewport)
	viewport.world_3d = get_world_3d()
	var camera := Camera3D.new()
	camera.cull_mask = 1
	viewport.add_child(camera)
	camera.current = true
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D reflection : source_color, filter_linear; uniform float live = 0.0; void fragment(){ ALBEDO = mix(vec3(0.14,0.17,0.16), texture(reflection, vec2(1.0-UV.x,UV.y)).rgb * vec3(0.88,0.94,0.93), live); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("reflection",viewport.get_texture())
	surface.material_override = material
	mirrors.append({"surface":surface,"viewport":viewport,"camera":camera,"center":center,"normal":normal,"right":right,"up":up,"size":bounds.size,"last_update":-100.0,"has_image":false})

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	if game.hud.menu.visible:
		for mirror in mirrors: mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		previous_position = game.player.global_position
		return
	avatar.global_position = game.player.global_position
	animate_body(delta)
	var restored: bool = game.flags.get("reflection_restored",false) or game.phase not in ["intro","news","to_dressing","mirror"]
	var home_host:bool=game.player.position.x>145 and not game.flags.get("rope_cut",false)
	var grinning: bool = home_host or (game.sequence_id == "mirror" and game.node_id in ["1","2"])
	if grinning != smile:
		smile = grinning
		for node in avatar.find_children("*", "MeshInstance3D", true, false):
			if String(node.name).begins_with("Uncanny"): node.visible = smile
			if String(node.name).begins_with("NeutralMouth"): node.visible = not smile
	reflection_clock += delta
	var eye: Vector3 = game.player.camera.global_position
	var visible: Array[int] = []
	var best := -1
	var best_score := -1.0
	for i in mirrors.size():
		var mirror: Dictionary = mirrors[i]
		mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		# One low-resolution viewport, only while the glass is on screen.
		if not surface_visible(mirror, game.player.camera, 10.0): continue
		visible.append(i)
		var alignment: float = -game.player.camera.global_basis.z.dot((mirror.center-eye).normalized())
		var score: float = alignment + (.01 if i == active_mirror else 0.0)
		if score > best_score:
			best_score = score; best = i
	active_mirror = best
	for i in mirrors.size():
		var mirror: Dictionary = mirrors[i]
		if i == best:
			update_reflection(mirror, eye, restored)
			mirror.last_update = reflection_clock
			mirror.has_image = true
		var material: ShaderMaterial = mirror.surface.material_override
		material.set_shader_parameter("live", 1.0 if i in visible and mirror.has_image else 0.0)

func surface_visible(mirror: Dictionary, camera: Camera3D, limit: float) -> bool:
	var offset: Vector3 = camera.global_position - mirror.center
	if offset.dot(mirror.normal) <= .02: return false
	var half_size: Vector2 = mirror.size * .5
	var nearest: Vector3 = mirror.center + mirror.right * clampf(offset.dot(mirror.right), -half_size.x, half_size.x) + mirror.up * clampf(offset.dot(mirror.up), -half_size.y, half_size.y)
	if camera.global_position.distance_squared_to(nearest) > limit * limit: return false
	# Test the full finite glass rectangle, not its centre. A visible edge can
	# remain on screen when the centre is outside, including close-up views.
	for plane in camera.get_frustum():
		var outside := true
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				var corner: Vector3 = mirror.center + mirror.right * half_size.x * x + mirror.up * half_size.y * y
				if plane.distance_to(corner) <= .01: outside = false
		if outside: return false
	return true

func update_reflection(mirror: Dictionary, eye: Vector3, restored: bool) -> void:
	var distance: float = (eye-mirror.center).dot(mirror.normal)
	var reflected: Vector3 = eye - 2.0*distance*mirror.normal
	var camera: Camera3D = mirror.camera
	camera.environment=game.player.camera.environment
	camera.global_transform = Transform3D(Basis(-mirror.right,mirror.up,-mirror.normal),reflected)
	var offset: Vector3 = mirror.center-reflected
	var near := distance+.015
	camera.set_frustum(mirror.size.y*near/distance,Vector2(offset.dot(-mirror.right),offset.dot(mirror.up))*near/distance,near,40)
	camera.cull_mask = 1 | (2 if restored else 0)
	mirror.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func animate_body(delta: float) -> void:
	var step: Vector3 = game.player.global_position - previous_position
	previous_position = game.player.global_position
	step.y = 0
	# Teleports and loading must not produce a running pose.
	var moving: bool = step.length() < .5 and not game.player.locked
	var velocity: Vector3 = game.player.get_real_velocity() if moving else Vector3.ZERO
	velocity.y = 0
	var speed: float = velocity.length()
	walk_weight = lerpf(walk_weight, clampf(speed / .65, 0, 1), 1.0-exp(-12.0*delta))
	if moving: gait += speed * delta * TAU / 1.65
	if step.length() >= .5 or game.player.locked:
		avatar.rotation.y = game.player.rotation.y + PI
	else:
		avatar.rotation.y = lerp_angle(avatar.rotation.y, game.player.rotation.y + PI, 1.0-exp(-14.0*delta))
	var local_step: Vector3 = avatar.global_basis.inverse() * velocity
	if speed > .05:
		walk_axis = walk_axis.lerp(Vector3(local_step.z, 0, -local_step.x).normalized(), 1.0-exp(-12.0*delta)).normalized()
	var axis := walk_axis
	for side in ["L", "R"]:
		var phase: float = gait + (PI if side == "R" else 0.0)
		pose_bone("thigh_"+side, axis, sin(phase)*.48*walk_weight)
		pose_bone("shin_"+side, Vector3.RIGHT, -maxf(0, -sin(phase))*.65*walk_weight)
		pose_bone("upper_"+side, axis, -sin(phase)*.24*walk_weight)
	pose_bone("spine", Vector3.FORWARD, sin(gait)*.025*walk_weight)

func pose_bone(name: String, axis: Vector3, angle: float) -> void:
	var bone: Dictionary = bone_data[name]
	var rest: Quaternion = bone.basis
	skeleton.set_bone_pose_rotation(bone.index, bone.pose * (rest.inverse() * Quaternion(axis,angle) * rest))

func begin_scene() -> void:
	if cinematic: return
	cinematic = true
	var camera: Camera3D = game.player.camera
	saved_rotation = camera.quaternion
	saved_fov = camera.fov
	var focus: Vector3 = camera.global_position-camera.global_basis.z*2
	if is_instance_valid(game.player.focus):
		focus = game.player.focus.to_global(game.player.focus.get_meta("focus_point",Vector3.ZERO))
	var selected: Dictionary = mirrors[0]
	for mirror in mirrors:
		if mirror.center.distance_squared_to(focus) < selected.center.distance_squared_to(focus): selected=mirror
	selected.viewport.size = Vector2i(224,int(224*selected.size.y/selected.size.x))
	var eye := camera.global_position
	var point: Vector3 = eye-selected.normal*(eye-selected.center).dot(selected.normal)
	camera.look_at(point,selected.up)
	var target := camera.quaternion
	camera.quaternion = saved_rotation
	camera_tween = create_tween().set_parallel(true)
	camera_tween.tween_property(camera,"quaternion",target,.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(camera,"fov",24.0,.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func end_scene() -> void:
	if not cinematic: return
	if camera_tween: camera_tween.kill()
	game.player.camera.quaternion = saved_rotation
	game.player.camera.fov = saved_fov
	cinematic = false
	for mirror in mirrors: mirror.viewport.size = Vector2i(160,int(160*mirror.size.y/mirror.size.x))
