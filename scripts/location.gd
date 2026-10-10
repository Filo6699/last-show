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
	# Supplied character illustrations replace anonymous blocking boxes.
	actor.get_node("Mesh").hide()
	var sprite := Sprite3D.new()
	sprite.name = "CharacterArt"
	sprite.texture = game.database.get_portrait(id)
	sprite.pixel_size = (3.1 if id == "bruno" else (2.05 if id == "elsa" else 2.5)) / sprite.texture.get_height()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.no_depth_test = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.shaded = true
	actor.add_child(sprite)
	if id == "elsa":
		var glow := OmniLight3D.new()
		glow.light_color = Color("a5c8e1");glow.light_energy = 1.6;glow.omni_range = 4
		glow.position = Vector3(0,0,1)
		actor.add_child(glow)
