extends Node3D
## Physical closed photo on the clinic wall. The still is rendered from the
## existing civilian Richard GLB, so the reveal cannot invent another face.
const PANEL_AT := Vector3(2.18, 0.0, 0.14)
const REVEALED_FLAG := "richard_photo_revealed"
const FALLEN_FLAG := "richard_photo_fallen"
const PENDING_FLAG := "photo_reveal_pending"
const LANDING_FLAG := "richard_photo_landing_transform"

var game: Node3D
var wall: StaticBody3D
var photo_card: Node3D
var paper_cover: Node3D
var caption: Label3D
var target: StaticBody3D
var transition: Tween
var floor_card_y := 0.0
var revealed := false
var fallen := false
var _ready_setup := false
var _interaction_session := -1
var held := false

func interact() -> void:
	if not _ready_setup or fallen or game.phase != "photos" or game.transitioning:
		return
	_interaction_session = int(game.session)
	held = false
	game.flags[PENDING_FLAG] = true
	game.player.set_locked(true)
	game.hud.close_dialog()
	game.hud.touch.hide()
	game.hud.crosshair.hide()
	game.transitioning = true
	reveal_child()
	game.sound("photo_take")
	game.save_game()
	var camera := game.player.camera as Camera3D
	var camera_basis := camera.global_basis.orthonormalized()
	var hand_position := camera.global_position - camera_basis.z * 0.9 + camera_basis.x * 0.15
	var hand_transform := Transform3D(camera_basis, hand_position)
	var forward := -camera_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_basis.x
	right.y = 0.0
	right = right.normalized()
	var drop_position := camera.global_position + forward * 0.9 + right * 0.15
	drop_position.y = 0.035
	var floor_transform := Transform3D(Basis(right, forward, Vector3.UP).orthonormalized(), drop_position)
	# Construct the entire sequential timeline before it starts; callbacks below
	# only update state and never append new tweeners.
	transition.set_parallel(false)
	transition.tween_interval(2.0)
	transition.tween_callback(_mark_held.bind(_interaction_session))
	transition.tween_property(photo_card, "global_transform", hand_transform, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_interval(2.0)
	transition.tween_callback(_mark_dropped.bind(_interaction_session, floor_transform))
	transition.tween_property(photo_card, "global_transform", floor_transform, 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	transition.tween_interval(0.55)
	transition.tween_callback(_complete_flow.bind(_interaction_session))

func _mark_held(token: int) -> void:
	if not _flow_is_current(token):
		return
	held = true
	game.save_game()

func _mark_dropped(token: int, floor_transform: Transform3D) -> void:
	if not _flow_is_current(token):
		return
	_set_dropped_state(floor_transform)
	photo_card.top_level = true
	game.sound("photo_drop")
	game.frame_player_at(landing_position(), .5)
	game.save_game()

func _complete_flow(token: int) -> void:
	if not _flow_is_current(token):
		return
	game.flags.erase(PENDING_FLAG)
	game.save_game()
	# update_staging()/sync() cancels the shared transition when the new phase
	# starts. Defer that phase switch until this tween callback has returned.
	call_deferred("_begin_walter_after_photo", token)

func _begin_walter_after_photo(token: int) -> void:
	if not is_instance_valid(game) or token != int(game.session) or game.phase != "photos" or bool(game.flags.get(PENDING_FLAG, false)):
		return
	game.begin_walter_arrival()

func _flow_is_current(token: int) -> bool:
	return is_instance_valid(game) and token == int(game.session) and game.phase == "photos" and game.transitioning and bool(game.flags.get(PENDING_FLAG, false))

func setup(owner_game: Node3D) -> void:
	if _ready_setup:
		return
	game = owner_game
	var candidates: Array = game.targets.get("photos", [])
	if candidates.is_empty() or not is_instance_valid(candidates[0]):
		push_error("clinic_photo_reveal: clinic photos wall target is missing")
		return
	wall = candidates[0] as StaticBody3D
	if get_parent() != wall:
		if get_parent(): get_parent().remove_child(self)
		wall.add_child(self)
	transform = Transform3D.IDENTITY
	name = "RichardChildPhotoReveal"
	floor_card_y = _floor_local_y() + 0.03
	_build_card()
	_build_cover()
	_build_target()
	_ready_setup = true
	sync()

func reveal_child() -> void:
	if not _ready_setup:
		return
	if fallen:
		return
	if revealed and is_instance_valid(transition) and transition.is_running():
		return
	revealed = true
	game.flags[REVEALED_FLAG] = true
	caption.visible = true
	if is_instance_valid(transition): transition.kill()
	transition = create_tween().set_parallel(true)
	transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# The blank sheet lifts from the top edge, slides down the wall, then settles
	# just below the picture. No dialogue text is needed to explain the action.
	transition.tween_property(paper_cover, "position:x", PANEL_AT.x - 0.95, 0.78)
	transition.tween_property(paper_cover, "position:y", _floor_local_y(), 0.78)
	transition.tween_property(paper_cover, "position:z", 0.72, 0.78)
	transition.tween_property(paper_cover, "rotation:x", -1.52, 0.78)

func drop_photo(destination: Variant = null) -> void:
	if not _ready_setup or fallen:
		return
	if not revealed:
		revealed = true
		game.flags[REVEALED_FLAG] = true
		caption.visible = true
		paper_cover.visible = false
	var end_transform: Transform3D
	if destination is Transform3D:
		end_transform = destination
	else:
		end_transform = Transform3D(photo_card.global_basis, landing_position())
	_set_dropped_state(end_transform)
	photo_card.top_level = true
	var world_end := end_transform
	# Do not replace the shared timeline from a callback: stop_effects() owns
	# cancellation and session changes make already-queued callbacks harmless.
	if not is_instance_valid(transition) or not transition.is_running():
		transition = create_tween()
	transition.set_parallel(true)
	transition.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Fall outward from the wall, then land flat enough for the face and caption
	# to remain readable from the clinic approach.
	transition.tween_property(photo_card, "global_transform", world_end, 0.72)

func _set_dropped_state(end_transform: Transform3D) -> void:
	fallen = true
	held = false
	target.collision_layer = 0
	game.flags[REVEALED_FLAG] = true
	game.flags[FALLEN_FLAG] = true
	game.flags[LANDING_FLAG] = _transform_to_array(end_transform)

func landing_position() -> Vector3:
	if not _ready_setup:
		return Vector3.ZERO
	if fallen and game.flags.has(LANDING_FLAG):
		return _array_to_transform(game.flags[LANDING_FLAG]).origin
	return wall.to_global(Vector3(PANEL_AT.x, floor_card_y, 0.88))

func sync() -> void:
	if not _ready_setup:
		return
	var saved_reveal := bool(game.flags.get(REVEALED_FLAG, false))
	var saved_fall := bool(game.flags.get(FALLEN_FLAG, false))
	revealed = saved_reveal or saved_fall
	fallen = saved_fall
	target.collision_layer = 0 if fallen else 16
	if is_instance_valid(transition): transition.kill()
	held = false
	photo_card.position = PANEL_AT
	photo_card.top_level = false
	photo_card.rotation = Vector3.ZERO
	caption.visible = revealed
	paper_cover.visible = true
	paper_cover.position = PANEL_AT
	paper_cover.rotation = Vector3.ZERO
	if revealed:
		paper_cover.position.x = PANEL_AT.x - 0.95
		paper_cover.position.y = _floor_local_y()
		paper_cover.position.z = 0.72
		paper_cover.rotation.x = -1.52
	if fallen:
		if game.flags.has(LANDING_FLAG):
			photo_card.top_level = true
			photo_card.global_transform = _array_to_transform(game.flags[LANDING_FLAG])
		else:
			photo_card.position = Vector3(PANEL_AT.x, _floor_local_y() + 0.03, 0.88)
			photo_card.rotation.x = -1.52

func reset() -> void:
	if is_instance_valid(transition): transition.kill()
	revealed = false
	fallen = false
	held = false
	_interaction_session = -1
	if game:
		game.flags.erase(REVEALED_FLAG)
		game.flags.erase(FALLEN_FLAG)
		game.flags.erase(PENDING_FLAG)
		game.flags.erase(LANDING_FLAG)
	if _ready_setup:
		target.collision_layer = 16
		photo_card.position = PANEL_AT
		photo_card.top_level = false
		photo_card.rotation = Vector3.ZERO
		paper_cover.position = PANEL_AT
		paper_cover.rotation = Vector3.ZERO
		paper_cover.visible = true
		caption.visible = false

func _floor_local_y() -> float:
	# Wall is mounted at clinic height; convert the world floor contact height
	# into this helper's local coordinates so the print actually lands at y≈0.
	return 0.03 - to_global(Vector3(PANEL_AT.x, 0.0, PANEL_AT.z)).y

func _transform_to_array(value: Transform3D) -> Array:
	var q := value.basis.get_rotation_quaternion()
	return [value.origin.x, value.origin.y, value.origin.z, q.x, q.y, q.z, q.w]

func _array_to_transform(value: Variant) -> Transform3D:
	if not value is Array or value.size() != 7:
		return Transform3D.IDENTITY
	var q := Quaternion(float(value[3]), float(value[4]), float(value[5]), float(value[6]))
	return Transform3D(Basis(q), Vector3(float(value[0]), float(value[1]), float(value[2])))

func _build_card() -> void:
	photo_card = Node3D.new()
	photo_card.name = "ChildRichardPhotograph"
	photo_card.position = PANEL_AT
	add_child(photo_card)
	var backing := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(0.80, 1.08, 0.05)
	backing.mesh = board
	backing.material_override = _mat(Color("392c27"), 0.86)
	photo_card.add_child(backing)
	var print := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.89)
	print.mesh = quad
	var print_material := StandardMaterial3D.new()
	print_material.albedo_texture = load("res://assets/story/photos/richard_child_portrait.png")
	print_material.albedo_color = Color("e8ddc4")
	print_material.roughness = 0.96
	print.material_override = print_material
	print.position.z = 0.029
	photo_card.add_child(print)
	caption = Label3D.new()
	caption.name = "ChildCaption"
	caption.text = "РЕБЁНОК"
	caption.font_size = 28
	caption.pixel_size = 0.0035
	caption.modulate = Color("e4d6bf")
	caption.position = Vector3(0, -0.62, 0.031)
	caption.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	caption.visible = false
	photo_card.add_child(caption)

func _build_cover() -> void:
	paper_cover = Node3D.new()
	paper_cover.name = "UncoveredPhotograph"
	paper_cover.position = PANEL_AT
	add_child(paper_cover)
	var paper := MeshInstance3D.new()
	var sheet := QuadMesh.new()
	sheet.size = Vector2(0.735, 0.905)
	paper.mesh = sheet
	paper.material_override = _mat(Color("9e9481"), 1.0)
	paper.position.z = 0.062
	paper_cover.add_child(paper)
	# A folded corner and two small paper tabs make the covered portrait read as
	# something the player can physically lift, while keeping it text-free.
	var tape_material := _mat(Color("b8aa89"), 1.0)
	for side in [-1.0, 1.0]:
		var tape := MeshInstance3D.new()
		var tape_mesh := BoxMesh.new()
		tape_mesh.size = Vector3(0.12, 0.035, 0.006)
		tape.mesh = tape_mesh
		tape.material_override = tape_material
		tape.position = Vector3(side * 0.255, 0.415, 0.068)
		tape.rotation.z = side * -0.12
		paper_cover.add_child(tape)
	var fold := MeshInstance3D.new()
	var fold_mesh := BoxMesh.new()
	fold_mesh.size = Vector3(0.11, 0.11, 0.009)
	fold.mesh = fold_mesh
	fold.material_override = _mat(Color("b9ac93"), 1.0)
	fold.position = Vector3(0.306, -0.39, 0.068)
	fold.rotation.z = 0.55
	paper_cover.add_child(fold)

func _build_target() -> void:
	target = StaticBody3D.new()
	target.name = "RichardChildPhotoInteractable"
	target.set_script(preload("res://scripts/interactable.gd"))
	target.interaction_id = &"photo_child"
	target.collision_layer = 16
	target.prompt = "Рассмотреть фотографию"
	target.position = PANEL_AT + Vector3(0, 0, -0.035)
	target.set_meta("focus_point", Vector3(0, 0, 0.035))
	target.set_meta("focus_range", 5.0)
	target.set_meta("outline_meshes", photo_card.find_children("*", "MeshInstance3D", true, false) + paper_cover.find_children("*", "MeshInstance3D", true, false))
	wall.add_child(target)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.88, 1.27, 0.15)
	collision.shape = shape
	target.add_child(collision)
	target.interacted.connect(game.on_interact)
	game.targets["photo_child"] = [target]

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
