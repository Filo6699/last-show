extends Node3D
## Planar reflections: shared 3D world, reflected eye, off-axis frustum.
## Layer 2 is Richard (hidden from his own camera); layer 4 is mirror glass.
var game
var avatar: Node3D
var mirrors: Array[Dictionary] = []
var elapsed := 0.0
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
	for animator in avatar.find_children("*","AnimationPlayer",true,false):
		for clip in animator.get_animation_list():
			if clip != "RESET":
				animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				animator.play(clip)
				break
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
	viewport.size = Vector2i(320, int(320*bounds.size.y/bounds.size.x))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.positional_shadow_atlas_size = 512
	add_child(viewport)
	viewport.world_3d = get_world_3d()
	var camera := Camera3D.new()
	camera.cull_mask = 1
	viewport.add_child(camera)
	camera.current = true
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D reflection : source_color, filter_linear; void fragment(){ ALBEDO = texture(reflection, vec2(1.0-UV.x,UV.y)).rgb * vec3(0.88,0.94,0.93); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("reflection",viewport.get_texture())
	surface.material_override = material
	mirrors.append({"surface":surface,"viewport":viewport,"camera":camera,"center":center,"normal":normal,"right":right,"up":up,"size":bounds.size})

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	avatar.global_position = game.player.global_position
	avatar.rotation.y = game.player.rotation.y + PI
	var restored: bool = game.flags.get("reflection_restored",false) or game.phase not in ["intro","news","to_dressing","mirror"]
	var grinning: bool = game.sequence_id == "mirror" and game.node_id in ["1","2"]
	if grinning != smile:
		smile = grinning
		for node in avatar.find_children("*", "MeshInstance3D", true, false):
			if String(node.name).begins_with("Uncanny"): node.visible = smile
			if String(node.name).begins_with("NeutralMouth"): node.visible = not smile
	elapsed += delta
	if elapsed < (1.0/30.0 if game.sequence_id == "mirror" else 1.0/15.0): return
	elapsed = 0
	var eye: Vector3 = game.player.camera.global_position
	for mirror in mirrors:
		var distance: float = (eye-mirror.center).dot(mirror.normal)
		if distance <= .10 or eye.distance_to(mirror.center) > 7.0 or not game.player.camera.is_position_in_frustum(mirror.center):
			mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		var reflected: Vector3 = eye - 2.0*distance*mirror.normal
		var camera: Camera3D = mirror.camera
		camera.global_transform = Transform3D(Basis(-mirror.right,mirror.up,-mirror.normal),reflected)
		var offset: Vector3 = mirror.center-reflected
		var near := distance+.015
		camera.set_frustum(mirror.size.y*near/distance,Vector2(offset.dot(-mirror.right),offset.dot(mirror.up))*near/distance,near,40)
		camera.cull_mask = 1 | (2 if restored else 0)
		mirror.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

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
	selected.viewport.size = Vector2i(512,int(512*selected.size.y/selected.size.x))
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
	for mirror in mirrors: mirror.viewport.size = Vector2i(320,int(320*mirror.size.y/mirror.size.x))
