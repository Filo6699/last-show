extends Node3D
## Physical staging shared by the story, capture tools and route tests.
var game
var gates: Dictionary = {}
var lamps: Array[OmniLight3D] = []
var motion := {}
var placements := {}
var gate_motion := {}
var gate_states := {}
var stage_show: Node3D

func setup(owner_game: Node3D) -> void:
	game = owner_game
	var points := [Vector3(-5,3.1,2), Vector3(0,4,-4), Vector3(4.5,3.1,-2), Vector3(-14.8,2.9,-.8), Vector3(-16,2.9,4), Vector3(-9.5,2.95,2.4), Vector3(6.6,2.9,2.4), Vector3(10.3,2.85,2.4), Vector3(14,2.85,2.4), Vector3(19,3,2.5)]
	for i in points.size():
		var light := OmniLight3D.new()
		light.position = points[i] - Vector3(0,.3,0)
		light.light_color = Color("ffd7a0") if i < 7 else Color("aecac2")
		light.light_energy = 1.25 if i < 7 else 1.35
		light.omni_range = 7 if i < 5 else 4.8
		light.omni_attenuation = 1.25
		light.shadow_enabled = i in [0,3,6]
		light.shadow_bias = .08
		light.shadow_normal_bias = 1.5
		add_child(light)
		lamps.append(light)
	# All visible mirrors support the same story action, including the small vanities.
	# Thin hit surfaces match their glass and do not block the approach to the table.
	for x in [-16.3, -12.6]:
		var target := StaticBody3D.new()
		target.set_script(preload("res://scripts/interactable.gd"))
		target.interaction_id = &"mirror"
		target.prompt = "Посмотреть на своё отражение"
		target.position = Vector3(x, 1.60, -1.105)
		add_child(target)
		var surface := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = Vector3(.65, .90, .08)
		surface.shape = bounds
		target.add_child(surface)
		target.interacted.connect(game.on_interact)
		game.targets["mirror"].append(target)
	gate("dressing", Vector3(-8,1.4,2.4), Color("502331"))
	gate("technical", Vector3(8,1.4,2.4), Color("304641"))
	# Actual photograph wall, accessible only after walking through the corridor.
	var photo_target := StaticBody3D.new()
	photo_target.set_script(preload("res://scripts/interactable.gd"))
	photo_target.interaction_id = &"photos"
	photo_target.prompt = "Рассмотреть фотографии"
	photo_target.position = Vector3(19,1.6,-.85)
	add_child(photo_target)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(4,1.8,.18)
	shape.shape = box; photo_target.add_child(shape)
	photo_target.interacted.connect(game.on_interact)
	game.targets["photos"] = [photo_target]
	for i in 3:
		var id: String = ["bruno","elsa","lili"][i]
		for row in 2:
			var frame := MeshInstance3D.new()
			var quad := QuadMesh.new();quad.size = Vector2(.86,.86)
			frame.mesh = quad
			var material := StandardMaterial3D.new()
			material.albedo_texture = game.database.get_photo(id,row==0)
			material.albedo_color = Color(.85,.83,.78) if material.albedo_texture else Color(.18,.17,.16)
			frame.material_override=material
			frame.position=Vector3((i-1)*1.35,.55-row*1.02,.12)
			photo_target.add_child(frame)
			var caption := Label3D.new();caption.text=("ДО" if row==0 else "ПОСЛЕ")+" · "+game.database.SPEAKERS[id]
			caption.font_size=32;caption.pixel_size=.003;caption.position=frame.position+Vector3(0,-.48,.015);photo_target.add_child(caption)
	var batches := Node3D.new()
	batches.name = "StaticEnvironmentBatches"
	add_child(batches)
	batches.set_meta("statistics", preload("res://scripts/static_batches.gd").apply(game.model, batches))
	stage_show=preload("res://scripts/stage_show.gd").new();add_child(stage_show);stage_show.setup(game)

func gate(id: String, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = id.capitalize()+"Door"
	body.set_script(preload("res://scripts/interactable.gd"))
	body.interaction_id = StringName(id)
	body.position = at
	body.set_meta("closed_position", at)
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new();box.size = Vector3(.12,2.8,2.78)
	mesh.mesh = box
	var material := StandardMaterial3D.new();material.albedo_color = color;material.roughness = .9
	mesh.material_override = material;body.add_child(mesh)
	if id == "dressing":
		for i in 14:
			var fold := MeshInstance3D.new()
			var pleat := BoxMesh.new();pleat.size = Vector3(.10,2.8,.16)
			fold.mesh = pleat;fold.material_override = material
			fold.position = Vector3(.085,0,-1.3+i*.2)
			fold.rotation.y = .35
			body.add_child(fold)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new();shape.size = box.size
	collision.shape = shape;body.add_child(collision)
	# Brass handle visually explains the action, without a floating marker.
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new();handle_mesh.size = Vector3(.18,.12,.35)
	handle.mesh = handle_mesh; handle.position = Vector3(-.1,-.1,.85)
	var brass := StandardMaterial3D.new();brass.albedo_color = Color("bba16c");brass.metallic = .65
	handle.material_override = brass;body.add_child(handle)
	body.interacted.connect(game.on_interact)
	game.targets[id] = [body]
	gates[id] = body

func sync() -> void:
	stage_show.sync_damage()
	var dressing_open: bool = game.flags.get("dressing_open", game.phase not in ["intro","news","to_dressing"])
	var technical_open: bool = game.flags.get("service_open", false)
	for id in gates:
		var opened: bool = dressing_open if id == "dressing" else technical_open
		var body: StaticBody3D = gates[id]
		body.visible = true
		var closed: Vector3 = body.get_meta("closed_position")
		var target: Vector3 = closed + (Vector3(0,0,-1.25) if id=="dressing" else Vector3(1.35,0,1.28)) if opened else closed
		var scale_z := .10 if opened and id=="dressing" else 1.0
		var angle := PI/2 if opened and id=="technical" else 0.0
		if not gate_states.has(id):
			body.position=target;body.scale.z=scale_z;body.rotation.y=angle;body.collision_layer=0 if opened else 1
		elif gate_states[id] != opened:
			if gate_motion.has(id): gate_motion[id].kill()
			body.collision_layer=1
			var tween := create_tween().set_parallel(true)
			tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(body,"position",target,1.0)
			tween.tween_property(body,"scale:z",scale_z,1.0)
			tween.tween_property(body,"rotation:y",angle,1.0)
			tween.chain().tween_callback(func(): body.collision_layer=0 if opened else 1)
			gate_motion[id]=tween
		gate_states[id]=opened
	gates.dressing.prompt = "Отодвинуть занавес" if game.phase not in ["intro","news"] else "Гримёрная — Мордекай ждёт ответа"
	gates.technical.prompt = "Открыть замок невидимкой" if game.flags.get("hairpin",false) else "Служебная дверь заперта"

func move_actor(id: String, target: Vector3, duration: float) -> void:
	var actor: Node3D=game.actors[id]
	if not placements.has(id): actor.position=target
	elif placements[id] != target:
		if motion.has(id): motion[id].kill()
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if id=="mordecai" and target.x > 0 and actor.position.x < 0:
			# Walk around the magic trunk, not through it.
			tween.tween_property(actor,"position",Vector3(-5.3,1.25,-3.2),2.4)
			tween.tween_property(actor,"position",target,3.6)
		elif id=="elsa" and actor.position.x < -11 and target.x > 0:
			# Follow the real doorway instead of flying through the dressing wall.
			tween.tween_property(actor,"position",Vector3(-13.2,2.1,2.4),1.0)
			tween.tween_property(actor,"position",Vector3(-7,2.1,2.4),3.5)
			tween.tween_property(actor,"position",target,5.0)
		else: tween.tween_property(actor,"position",target,duration)
		motion[id]=tween
	placements[id]=target

func reset_motion() -> void:
	for tween in motion.values(): tween.kill()
	for tween in gate_motion.values(): tween.kill()
	motion.clear();placements.clear();gate_motion.clear();gate_states.clear()
	if is_instance_valid(stage_show): stage_show.reset()

func opening_action(action: String) -> void: stage_show.opening_action(action)
func roof_crack() -> void: stage_show.roof_crack()

func actor_visual(id: String, actor: Node3D) -> void:
	var placeholder := actor.get_node_or_null("Mesh")
	if placeholder: placeholder.hide()
	var model: Node3D = load("res://assets/characters/models/"+id+".glb").instantiate()
	model.name = "CharacterArt"
	model.position.y = -{"mordecai":1.25,"bruno":1.55,"lili":1.2,"elsa":1.2,"walter":.95}[id]
	actor.add_child(model)
	if id == "elsa":
		model.scale = Vector3.ONE*.70
		# Airborne limbs close to the lamp otherwise cover the entire ceiling in
		# oversized hard shadows; keep the dressing props as shadow casters.
		for mesh in model.find_children("*","MeshInstance3D",true,false): mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if id == "mordecai":
		for mouth in model.find_children("NeutralMouth*","MeshInstance3D",true,false): mouth.hide()
	for animator in model.find_children("*","AnimationPlayer",true,false):
		for clip in animator.get_animation_list():
			if clip != "RESET":
				animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				animator.play(clip)
				break
	var shape := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		shape.scale = Vector3.ONE
		var capsule := CapsuleShape3D.new()
		capsule.radius = .70 if id=="mordecai" else (.55 if id=="elsa" else (.40 if id == "bruno" else .27))
		capsule.height = {"bruno":2.30,"lili":1.42,"elsa":1.9,"mordecai":2.05,"walter":1.86}[id]
		shape.shape = capsule
		shape.position.y = model.position.y + capsule.height/2
	if id == "elsa":
		var rope := MeshInstance3D.new()
		rope.name = "Suspension"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = .009; cylinder.bottom_radius = .009; cylinder.radial_segments = 6
		rope.mesh = cylinder
		var material := StandardMaterial3D.new(); material.albedo_color = Color("63543b")
		rope.material_override = material
		actor.add_child(rope)
		var glow := OmniLight3D.new()
		glow.light_color = Color("a5c8e1");glow.light_energy = 1.6;glow.omni_range = 4
		glow.position = Vector3(0,0,1)
		actor.add_child(glow)

func pause_motion(value: bool) -> void:
	for tween in motion.values()+gate_motion.values():
		if tween and tween.is_valid():
			if value: tween.pause()
			else: tween.play()
	stage_show.pause_motion(value)
