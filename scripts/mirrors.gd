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
	# The small mirrors are part of joined vanity meshes. Overlay their exact oval.
	for x in [-16.3, -12.6]:
		var surface := MeshInstance3D.new()
		var vertices := PackedVector3Array([Vector3.ZERO])
		for i in 24:
			var angle := TAU * i / 24
			vertices.append(Vector3(.315*cos(angle), .435*sin(angle), 0))
		var indices := PackedInt32Array()
		for i in 24: indices.append_array(PackedInt32Array([0,i+1,(i+1)%24+1]))
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		surface.mesh = mesh
		surface.position = Vector3(x,1.60,-1.098)
		add_child(surface)
		add_surface(surface)
		# Hit targets live under Location; expose the actual glass for silhouette selection.
		for target in game.targets.get("mirror", []):
			if not target.has_meta("source_mesh") and target.global_position.distance_to(surface.global_position) < .03:
				target.set_meta("outline_meshes", [surface])

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
	mirrors.append({"surface":surface,"viewport":viewport,"camera":camera,"center":center,"normal":normal,"right":right,"up":up,"size":bounds.size})

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	if game.hud.menu.visible:
		for mirror in mirrors: mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		previous_position = game.player.global_position
		return
	avatar.global_position = game.player.global_position
	animate_body(delta)
	var restored: bool = game.flags.get("reflection_restored",false) or game.phase not in ["intro","news","to_dressing","mirror"]
	var grinning: bool = game.sequence_id == "mirror" and game.node_id in ["1","2"]
	if grinning != smile:
		smile = grinning
		for node in avatar.find_children("*", "MeshInstance3D", true, false):
			if String(node.name).begins_with("Uncanny"): node.visible = smile
			if String(node.name).begins_with("NeutralMouth"): node.visible = not smile
	# One live reflection at display cadence: spend fewer pixels, not fewer frames.
	var eye: Vector3 = game.player.camera.global_position
	var best := -1
	var best_score := -1.0
	for i in mirrors.size():
		var mirror: Dictionary = mirrors[i]
		mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var distance: float = (eye-mirror.center).dot(mirror.normal)
		if distance <= .10 or eye.distance_to(mirror.center) > 7.0 or not game.player.camera.is_position_in_frustum(mirror.center): continue
		var alignment: float = -game.player.camera.global_basis.z.dot((mirror.center-eye).normalized())
		var score: float = alignment + (.06 if i == active_mirror else 0.0)
		if score > best_score:
			best_score = score; best = i
	active_mirror = best
	for i in mirrors.size():
		var mirror: Dictionary = mirrors[i]
		var material: ShaderMaterial = mirror.surface.material_override
		material.set_shader_parameter("live", 1.0 if i == best else 0.0)
		if i != best: continue
		var distance: float = (eye-mirror.center).dot(mirror.normal)
		var reflected: Vector3 = eye - 2.0*distance*mirror.normal
		var camera: Camera3D = mirror.camera
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
