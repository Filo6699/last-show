extends Node3D
## Physical staging shared by the story, capture tools and route tests.
var game
var gates: Dictionary = {}
var lamps: Array[OmniLight3D] = []

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
		var frame := MeshInstance3D.new()
		var quad := QuadMesh.new();quad.size = Vector2(.95,1.35)
		frame.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_texture = game.database.get_portrait(["bruno","elsa","lili"][i])
		material.albedo_color = Color(.9,.9,.82)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		frame.material_override = material
		frame.position = Vector3((i-1)*1.35,0,.12)
		photo_target.add_child(frame)
		var backing := MeshInstance3D.new()
		var panel := BoxMesh.new();panel.size = Vector3(1.05,1.45,.06)
		backing.mesh = panel
		var paper := StandardMaterial3D.new();paper.albedo_color = Color("b0af98")
		backing.material_override = paper
		backing.position = frame.position - Vector3(0,0,.04)
		photo_target.add_child(backing)

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
	var dressing_open: bool = game.phase not in ["intro","news"]
	var technical_open: bool = game.flags.get("service_open", false)
	for id in gates:
		var opened: bool = dressing_open if id == "dressing" else technical_open
		gates[id].visible = true
		gates[id].collision_layer = 0 if opened else 1
		var closed: Vector3 = gates[id].get_meta("closed_position")
		if id == "dressing":
			gates[id].position = closed + Vector3(0,0,-1.25) if opened else closed
			gates[id].scale.z = .10 if opened else 1.0
		else:
			gates[id].position = closed + Vector3(1.35,0,1.28) if opened else closed
			gates[id].rotation.y = PI/2 if opened else 0.0
	gates.dressing.prompt = "Гримёрная — Мордекай ждёт ответа"
	gates.technical.prompt = "Открыть замок невидимкой" if game.flags.get("hairpin",false) else "Служебная дверь заперта"

func actor_visual(id: String, actor: Node3D) -> void:
	var placeholder := actor.get_node_or_null("Mesh")
	if placeholder: placeholder.hide()
	var model: Node3D = load("res://assets/characters/models/"+id+".glb").instantiate()
	model.name = "CharacterArt"
	model.position.y = -{"mordecai":1.25,"bruno":1.55,"lili":1.2,"elsa":1.2,"walter":.95}[id]
	actor.add_child(model)
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
		capsule.radius = .40 if id == "bruno" else .27
		capsule.height = {"bruno":2.30,"lili":1.42,"elsa":1.9,"mordecai":1.8,"walter":1.86}[id]
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
