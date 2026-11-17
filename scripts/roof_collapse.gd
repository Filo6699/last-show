extends Node3D
## After Richard cuts the rope the tent starts to come apart. The medicine bag
## drops forty metres onto the ring, then the catwalk shudders every few
## seconds: creaks, canvas and boards fall past him, the roof lamps go out one
## by one. Once he reaches the trampoline board the boards give way after
## DEADLINE seconds, and he goes through the canopy anyway.
const DEADLINE := 25.0
const BAG_FALL := 2.9
const RING_Y := .0
# Lamps go out in this order; the trampoline lamp only flickers.
const LAMP_ORDER := [Vector3(-10, 42.3, -17), Vector3(6.5, 42.3, -11), Vector3(-10, 42.3, -5)]

var game
var late
var rng := RandomNumberGenerator.new()
var active := false
var jolt_wait := 2.0
var shake := 0.0
var shake_time := 0.0
var countdown := -1.0
var warned := false
var lamps_out := 0
var falling_bits: Array[Node3D] = []
var debris_material: StandardMaterial3D
var canvas_materials: Array[StandardMaterial3D] = []
var look_tween: Tween

func setup(owner_game, owner_late) -> void:
	game = owner_game; late = owner_late; name = "RoofCollapse"
	rng.randomize()
	debris_material = StandardMaterial3D.new(); debris_material.albedo_color = Color("3b3129")
	for hex in ["8e2a35", "d8cdb8"]:
		var cloth := StandardMaterial3D.new(); cloth.albedo_color = Color(hex)
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		canvas_materials.append(cloth)

func wanted() -> bool:
	return game.phase == "roof" and game.flags.get("rope_cut", false) and late.is_roof_position(game.player.global_position)

func _process(delta: float) -> void:
	var now := wanted()
	if now != active:
		active = now
		if not active: stop()
	update_shake(delta)
	if not active or game.transitioning: return
	var talking: bool = not game.sequence_id.is_empty()
	jolt_wait -= delta
	if jolt_wait <= 0 and not talking:
		jolt_wait = rng.randf_range(3.5, 6.0) if countdown < 0 else rng.randf_range(2.0, 3.5)
		jolt()
	# The clock only runs on the trampoline board: the wire stays a balance
	# test, not a race.
	if game.player.global_position.x > late.WIRE_B + .6:
		if countdown < 0:
			countdown = DEADLINE
			game.hud.show_notice("Доски ходят под ногами. Прыгай, пока помост держит.")
		elif not talking:
			countdown -= delta
			if countdown < 9 and not warned:
				warned = true
				game.hud.show_notice("Помост трещит.")
				game.audio.play("sfx_creak_wood_0%d" % rng.randi_range(1, 5), -2)
			if countdown <= 0: give_way()

## Called by the cut_rope event: the bag falls and Richard watches it go.
func drop_bag() -> void:
	var bag: Node3D = late.medicine_bag
	# Land on whatever is under the rope: the ring, or a set piece on it.
	var from: Vector3 = late.ROPE - Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, -2, from.z), 1, [game.player.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	var floor_y: float = hit.position.y if not hit.is_empty() else RING_Y
	# The bag box hangs .35 below the rope end and is .65 tall.
	var drop: float = floor_y + .33 - (late.ROPE.y - .35)
	var tween := create_tween()
	tween.tween_property(bag, "position:y", drop, BAG_FALL).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		game.audio.play("sfx_box_bump_0%d" % rng.randi_range(1, 2), -10)
		game.audio.play("sfx_roof_debris_0%d" % rng.randi_range(1, 3), -14)
		bag.hide())
	follow_bag(bag)

func follow_bag(bag: Node3D) -> void:
	var player: Node3D = game.player
	var camera: Camera3D = player.camera
	var target: Vector3 = late.ROPE
	var d: Vector3 = target - player.global_position
	var yaw_from: float = player.rotation.y
	var yaw_to := atan2(-d.x, -d.z)
	var pitch_from: float = camera.rotation.x
	if look_tween: look_tween.kill()
	look_tween = create_tween()
	look_tween.tween_method(func(t: float):
		player.rotation.y = lerp_angle(yaw_from, yaw_to, t)
		camera.rotation.x = lerpf(pitch_from, -.75, t), 0.0, 1.0, .45).set_trans(Tween.TRANS_SINE)
	# Then track the bag down as it falls.
	look_tween.tween_method(func(_t: float):
		var eye: Vector3 = camera.global_position
		var at: Vector3 = bag.global_position + Vector3(0, -.35, 0)
		var flat := Vector2(at.x - eye.x, at.z - eye.z).length()
		camera.rotation.x = clampf(-atan2(eye.y - at.y, maxf(flat, .01)), -1.45, .2), 0.0, 1.0, BAG_FALL - .2)
	look_tween.tween_interval(.5)
	look_tween.tween_property(camera, "rotation:x", -.1, .9).set_trans(Tween.TRANS_SINE)

func jolt() -> void:
	shake = rng.randf_range(.035, .06); shake_time = .6
	var sounds := ["sfx_creak_wood_0%d" % rng.randi_range(1, 5), "sfx_elsa_rig_creak_0%d" % rng.randi_range(1, 3), "sfx_canvas_flap_0%d" % rng.randi_range(1, 3), "sfx_roof_crack"]
	game.audio.play(sounds[rng.randi_range(0, sounds.size() - 1)], -4)
	if rng.randf() < .6: game.audio.play("sfx_roof_debris_0%d" % rng.randi_range(1, 3), -10)
	for i in rng.randi_range(2, 4): drop_piece(i == 0)
	next_lamp()

# A board splinter or a strip of canvas falls past the catwalk, within view.
func drop_piece(canvas: bool) -> void:
	var player: Node3D = game.player
	var forward: Vector3 = -player.global_transform.basis.z; forward.y = 0
	forward = forward.normalized() if forward.length() > .01 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	var start: Vector3 = player.global_position + forward * rng.randf_range(2.5, 6.0) + side * rng.randf_range(-3.0, 3.0) + Vector3(0, rng.randf_range(6.0, 9.0), 0)
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	if canvas:
		mesh.size = Vector3(rng.randf_range(.5, 1.0), .015, rng.randf_range(1.2, 2.2))
		piece.material_override = canvas_materials[rng.randi_range(0, 1)]
	else:
		mesh.size = Vector3(rng.randf_range(.08, .2), rng.randf_range(.05, .1), rng.randf_range(.5, 1.4))
		piece.material_override = debris_material
	piece.mesh = mesh
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	piece.global_position = start
	piece.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	falling_bits.append(piece)
	var time := 2.8 if canvas else 2.2
	var tween := piece.create_tween()
	tween.tween_property(piece, "global_position:y", start.y - 46.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(piece, "rotation", piece.rotation + Vector3(rng.randf_range(-4, 4), rng.randf_range(-6, 6), rng.randf_range(-4, 4)), time)
	if canvas:
		tween.parallel().tween_property(piece, "global_position:x", start.x + rng.randf_range(-2.0, 2.0), time)
	tween.tween_callback(func():
		falling_bits.erase(piece)
		piece.queue_free())

func lamp_near(at: Vector3) -> OmniLight3D:
	for light in late.find_children("*", "OmniLight3D", true, false):
		if light.global_position.distance_to(at) < .6: return light
	return null

func next_lamp() -> void:
	if lamps_out >= LAMP_ORDER.size(): return
	var at: Vector3 = LAMP_ORDER[lamps_out]
	# The lamp over the wire stays on until Richard is across.
	if lamps_out == 2 and game.player.global_position.x < late.WIRE_B: return
	if rng.randf() < .4: return
	lamps_out += 1
	var light := lamp_near(at)
	if light == null: return
	var bulbs: Array[Node] = []
	for node in late.get_children():
		if node is MeshInstance3D and node.global_position.distance_to(light.global_position) < .05: bulbs.append(node)
	game.audio.play("sfx_light_flicker_0%d" % rng.randi_range(1, 3), -6)
	var energy := light.light_energy
	var tween := create_tween()
	for level in [.2, 1.0, .1, .6, 0.0]:
		tween.tween_callback(func(): light.light_energy = energy * level)
		tween.tween_interval(rng.randf_range(.06, .14))
	tween.tween_callback(func():
		light.visible = false
		for bulb in bulbs: bulb.visible = false)

func update_shake(delta: float) -> void:
	var camera: Camera3D = game.player.camera
	if shake_time <= 0:
		return
	shake_time -= delta
	var t := Time.get_ticks_msec() * .001
	var amount := shake * clampf(shake_time / .6, 0, 1)
	camera.h_offset = sin(t * 31.0) * amount
	camera.v_offset = sin(t * 27.0 + 1.7) * amount
	if shake_time <= 0:
		camera.h_offset = 0; camera.v_offset = 0

func give_way() -> void:
	countdown = -1.0
	game.hud.show_notice("Доски уходят из-под ног.")
	game.audio.play("sfx_roof_crack", 0)
	shake = .09; shake_time = 1.2
	game.flags.roof_choice = "jump"
	game.full_game.jump_home()

func stop() -> void:
	countdown = -1.0
	warned = false
	shake_time = 0
	if look_tween: look_tween.kill()
	game.player.camera.h_offset = 0; game.player.camera.v_offset = 0
	for piece in falling_bits:
		if is_instance_valid(piece): piece.queue_free()
	falling_bits.clear()

## A new run or a loaded save: lamps back on, collapse state cleared.
func reset() -> void:
	stop()
	active = false
	lamps_out = 0
	jolt_wait = 2.0
	for at in LAMP_ORDER:
		var light := lamp_near(at)
		if light == null: continue
		light.visible = true
		for node in late.get_children():
			if node is MeshInstance3D and node.global_position.distance_to(light.global_position) < .05: node.visible = true
