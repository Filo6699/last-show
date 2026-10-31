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
var lighting: Node3D
var mordecai_attention

func setup(owner_game: Node3D) -> void:
	game = owner_game
	lighting=preload("res://scripts/circus_lighting.gd").new()
	add_child(lighting);lighting.setup(game);lamps=lighting.lamps
	# Vanity interaction/reflection surfaces are derived from the authored meshes
	# by mirrors.gd; furniture no longer moves to fit hardcoded glass coordinates.
	gate("dressing", game.layout.DRESSING_GATE, Color("502331"))
	gate("technical", game.layout.TECHNICAL_GATE, Color("304641"))
	# Actual photograph wall, accessible only after walking through the corridor.
	var photo_target := StaticBody3D.new()
	photo_target.set_script(preload("res://scripts/interactable.gd"))
	photo_target.interaction_id = &"photos"
	photo_target.prompt = "Рассмотреть фотографии"
	photo_target.collision_layer = 0
	photo_target.position = game.layout.PHOTOS
	photo_target.rotation.y=-PI/2
	add_child(photo_target)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(4,1.8,.18)
	shape.shape = box; photo_target.add_child(shape)
	photo_target.interacted.connect(game.on_interact)
	game.targets["photos"] = [photo_target]
	for i in 3:
		var id: String = ["bruno","elsa","lili"][i]
		var pair := StaticBody3D.new()
		pair.name = "PhotoPair" + id.capitalize()
		pair.set_script(preload("res://scripts/interactable.gd"))
		pair.interaction_id = StringName("photo_" + id)
		pair.prompt = "Рассмотреть фотографию"
		pair.collision_layer = 16
		pair.position = Vector3((i-1)*1.35, .55, .15)
		var hitbox := CollisionShape3D.new()
		var bounds := BoxShape3D.new(); bounds.size = Vector3(1.05, 1.1, .12)
		hitbox.shape = bounds
		photo_target.add_child(pair); pair.add_child(hitbox)
		pair.interacted.connect(game.on_interact)
		game.targets["photo_" + id] = [pair]
		var prints: Array[MeshInstance3D] = []
		for row in 1:
			var frame := MeshInstance3D.new()
			var quad := QuadMesh.new();quad.size = Vector2(.86,.86)
			frame.mesh = quad
			var material := StandardMaterial3D.new()
			material.albedo_texture = game.database.get_photo(id,true)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material.albedo_color = Color(.85,.83,.78) if material.albedo_texture else Color(.18,.17,.16)
			frame.material_override=material
			frame.position=Vector3((i-1)*1.35,.55-row*1.02,.12)
			photo_target.add_child(frame)
			prints.append(frame)
			var caption := Label3D.new();caption.text="ДО · "+game.database.SPEAKERS[id]
			caption.font_size=32;caption.pixel_size=.003;caption.position=frame.position+Vector3(0,-.48,.015);photo_target.add_child(caption)
		pair.set_meta("outline_meshes", prints)
	# The supplied covered print is replaced by the animated physical card.
	# Hide its old coplanar paper/frame before static batching, including colliders.
	for source in game.model.find_children("*", "MeshInstance3D", true, false):
		if String(source.name).begins_with("Covered photo"):
			source.hide()
	for collider in game.model.get_node("GeometryCollisions").get_children():
		if String(collider.get_meta("source_mesh", "")).begins_with("Covered photo"):
			collider.collision_layer = 0
	var boundaries := preload("res://scripts/feedback_boundaries.gd").new()
	add_child(boundaries)
	boundaries.setup(game)
	build_annex_roofs()
	build_passage()
	var backstage := preload("res://scripts/backstage.gd").new()
	add_child(backstage)
	backstage.setup(game)
	preload("res://scripts/set_finish_materials.gd").apply_authored(game.model)
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
	body.rotation.y=game.layout.DRESSING_YAW if id=="dressing" else -PI/2
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new();box.size = Vector3(.12,2.8,2.60 if id == "technical" else 2.78)
	mesh.mesh = box
	var material := StandardMaterial3D.new();material.albedo_color = color;material.roughness = .9
	mesh.material_override = material;body.add_child(mesh)
	if id == "dressing":
		mesh.mesh = curtain_mesh()
		mesh.material_override = preload("res://scripts/set_finish_materials.gd").make_surface(color,&"cloth")
		mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		# The rail stays fixed when the fabric compresses and slides aside.
		var rail := MeshInstance3D.new()
		var rail_mesh := CylinderMesh.new()
		rail_mesh.top_radius=.025;rail_mesh.bottom_radius=.025;rail_mesh.height=2.95;rail_mesh.radial_segments=8
		rail.mesh=rail_mesh;rail.material_override=material.duplicate()
		rail.material_override.albedo_color=Color("817154");rail.material_override.metallic=.45
		rail.position=at+Vector3(0,1.48,0);rail.rotation=Vector3(PI/2,game.layout.DRESSING_YAW,0)
		add_child(rail)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new();shape.size = box.size
	collision.shape = shape;body.add_child(collision)
	# Brass handle visually explains the action, without a floating marker.
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new();handle_mesh.size = Vector3(.18,.12,.35)
	handle.mesh = handle_mesh; handle.position = Vector3(-.1,-.1,-.85 if id == "technical" else .85)
	var brass := StandardMaterial3D.new();brass.albedo_color = Color("bba16c");brass.metallic = .65
	handle.material_override = brass;body.add_child(handle)
	if id == "dressing":
		var pull := CylinderMesh.new();pull.top_radius=.012;pull.bottom_radius=.012;pull.height=.9;pull.radial_segments=8
		handle.mesh=pull;handle.position=Vector3(-.19,-.45,.98)
		brass.albedo_color=Color("c2aa7d");brass.metallic=0;brass.roughness=.95
	else:
		# Lever handle on both faces at hand height instead of a brass brick.
		var edge := -.85 if id == "technical" else .85
		var plate_mesh := BoxMesh.new();plate_mesh.size = Vector3(.02,.2,.06)
		var lever_mesh := CylinderMesh.new();lever_mesh.top_radius=.014;lever_mesh.bottom_radius=.014;lever_mesh.height=.13;lever_mesh.radial_segments=8
		handle.mesh = plate_mesh;handle.position = Vector3(-.07,-.4,edge)
		for side in [-1.0,1.0]:
			if side > 0:
				var plate := MeshInstance3D.new();plate.mesh=plate_mesh;plate.material_override=brass
				plate.position=Vector3(.07,-.4,edge);body.add_child(plate)
			var lever := MeshInstance3D.new();lever.mesh=lever_mesh;lever.material_override=brass
			lever.position=Vector3(side*.11,-.36,edge-signf(edge)*.05);lever.rotation.x=PI/2
			body.add_child(lever)
	if id == "technical":
		# Hinge at the corridor-side jamb. The entire leaf rotates into +X,
		# while its thickness stays inside the corridor's z=3.725 inner wall.
		var hinge_offset := Vector3(.06,0,1.30)
		body.position = at + body.basis*hinge_offset
		body.set_meta("closed_position", body.position)
		body.set_meta("focus_point", -hinge_offset)
		for child in body.get_children():
			if child is Node3D: child.position -= hinge_offset
	body.interacted.connect(game.on_interact)
	game.targets[id] = [body]
	gates[id] = body

func curtain_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(0)
	var columns := 64
	var rows := 10
	for row in rows:
		for column in columns:
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var u := float(column+corner.x)/columns
				var v := float(row+corner.y)/rows
				var pleat := cos(u*TAU*10.0)
				var depth := -.055+pleat*(.062+.025*sin(v*PI))
				var hem := sin(u*TAU*10.0)*.014*(1.0-v)
				builder.set_uv(Vector2(u*3.0,v))
				builder.add_vertex(Vector3(depth,-1.37+v*2.75+hem,-1.39+u*2.78))
	builder.generate_normals()
	return builder.commit()

func sync() -> void:
	lighting.sync()
	stage_show.sync_damage()
	var dressing_open: bool = game.flags.get("dressing_open", game.phase not in ["intro","news","to_dressing"])
	var technical_open: bool = game.flags.get("service_open", false)
	for id in gates:
		var opened: bool = dressing_open if id == "dressing" else technical_open
		var body: StaticBody3D = gates[id]
		body.visible = true
		var closed: Vector3 = body.get_meta("closed_position")
		# body.basis includes its compressed scale after the curtain has opened.
		# Use the authored rotation axis so staging resets always park it fully aside.
		var dressing_axis:=Basis(Vector3.UP,game.layout.DRESSING_YAW).z
		var target: Vector3 = closed + dressing_axis*(-1.25) if opened and id=="dressing" else closed
		var scale_z := .10 if opened and id=="dressing" else 1.0
		var angle: float = (-PI/2 + (-PI/2 if opened else 0.0)) if id=="technical" else game.layout.DRESSING_YAW
		if not gate_states.has(id):
			body.position=target;body.scale.z=scale_z;body.rotation.y=angle;body.collision_layer=0 if opened else 1
		elif gate_states[id] != opened:
			if gate_motion.has(id): gate_motion[id].kill()
			body.collision_layer=1
			var tween := create_tween().set_parallel(true)
			tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			var delay := 1.0 if id=="technical" and opened and game.phase in ["return_arena", "roof_access"] else 0.0
			tween.tween_property(body,"position",target,1.0).set_delay(delay)
			tween.tween_property(body,"scale:z",scale_z,1.0).set_delay(delay)
			tween.tween_property(body,"rotation:y",angle,1.0).set_delay(delay)
			tween.chain().tween_callback(func(): body.collision_layer=0 if opened else 1)
			gate_motion[id]=tween
		gate_states[id]=opened
	gates.dressing.prompt = "Отодвинуть занавес" if game.phase not in ["intro","news"] else "Гримёрная закрыта"
	if technical_open:
		gates.technical.prompt = "Служебный коридор"
	elif game.phase in ["elsa_hall", "to_technical"]:
		gates.technical.prompt = "Открыть служебную дверь"
	else:
		gates.technical.prompt = "Открыть замок невидимкой" if game.flags.get("hairpin",false) else "Служебная дверь заперта"

func move_actor(id: String, target: Vector3, duration: float) -> void:
	var actor: Node3D=game.actors[id]
	if not placements.has(id): actor.position=target
	elif placements[id] != target and duration <= 0.0:
		# Off-screen relocation: no visible walk.
		if motion.has(id): motion[id].kill();motion.erase(id)
		actor.position=target
	elif placements[id] != target:
		if motion.has(id): motion[id].kill()
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if id=="elsa" and target==game.layout.ELSA_HALL:
			tween.tween_property(actor,"position",Vector3(-40,2.1,43),2.0)
			tween.tween_property(actor,"position",Vector3(-33,2.1,39.5),3.5)
			tween.tween_property(actor,"position",target,3.0)
		else: tween.tween_property(actor,"position",target,duration)
		motion[id]=tween
	placements[id]=target

func reset_motion() -> void:
	for tween in motion.values(): tween.kill()
	for tween in gate_motion.values(): tween.kill()
	motion.clear();placements.clear();gate_motion.clear();gate_states.clear()
	if is_instance_valid(stage_show): stage_show.reset()
	if is_instance_valid(mordecai_attention): mordecai_attention.reset_attention()

func opening_action(action: String) -> void: stage_show.opening_action(action)
func roof_crack() -> void: stage_show.roof_crack()

func actor_visual(id: String, actor: Node3D) -> void:
	var placeholder := actor.get_node_or_null("Mesh")
	if placeholder: placeholder.hide()
	var model_path := "res://assets/characters/models/"+id+".glb"
	if id == "mordecai" and ResourceLoader.exists("res://assets/characters/models/mordecai_attention.glb"):
		model_path = "res://assets/characters/models/mordecai_attention.glb"
	var model: Node3D = load(model_path).instantiate()
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
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			mordecai_attention = preload("res://scripts/actor_attention.gd").new()
			mordecai_attention.name = "NewsAttention"
			actor.add_child(mordecai_attention)
			mordecai_attention.setup(game, actor, skeletons[0], model)
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
	lighting.pause_motion(value)
	if is_instance_valid(mordecai_attention): mordecai_attention.set_paused(value)

func build_passage() -> void:
	# The supplied tents have separate doorways; this short canvas passage joins
	# the opening cut in the main canvas to the dressing tent's existing opening.
	var passage := Node3D.new()
	passage.name="DressingPassage"
	add_child(passage)
	passage.position=Vector3(-28,0,37)
	passage.rotation.y=game.layout.DRESSING_YAW
	var parts:=preload("res://scripts/scene_parts.gd").new()
	passage.add_child(parts)
	var wall_material:=StandardMaterial3D.new()
	wall_material.albedo_color=Color("3b3037");wall_material.roughness=.96
	# The prepared canvas portals are only cut below y=3.4 and within |z|<1.65.
	# Keep the added tunnel inside that opening so its roof and frame do not poke
	# through the artist's untouched canvas. The right wall ends before the
	# authored vanity at the dressing-room mouth, leaving the exit flared open.
	for side in [-1,1]:
		# Both walls run into the dressing tent canvas; no gap to the yard.
		var length:float=13.1 if side<0 else 10.8
		var center_x:float=length*.5
		var wall:=MeshInstance3D.new()
		var wall_mesh:=BoxMesh.new();wall_mesh.size=Vector3(length,3.22,.12)
		wall.mesh=wall_mesh;wall.position=Vector3(center_x,1.61,side*1.48)
		wall.material_override=wall_material;passage.add_child(wall)
		var body:=StaticBody3D.new();wall.add_child(body)
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=wall_mesh.size
		collision.shape=shape;body.add_child(collision)
		# Fine brass reveals turn the dark side panels into an intentional frame.
		for y in [.12,3.08]:
			parts.box(Vector3(center_x,y,side*1.405),Vector3(length,.035,.018),"897451")
		for index in 3:
			var at_x:=2.0+index*3.05
			if side>0 and at_x>length-.6:continue
			var poster:=preload("res://scripts/scene_parts.gd").new();passage.add_child(poster)
			poster.position=Vector3(at_x,1.95,side*1.405);poster.rotation.y=PI if side==1 else 0
			poster.box(Vector3.ZERO,Vector3(.90,1.36,.025),"aa9875")
			for edge in [-1,1]:poster.box(Vector3(edge*.41,0,.02),Vector3(.025,1.28,.015),"51343b")
			var names:=["БРУНО","ЭЛЬЗА","ЛИЛИ"]
			var paths:=["res://assets/characters/colored/bruno.png","res://assets/characters/colored/elsa.png","res://assets/characters/colored/lili.png"]
			poster.sign_text(names[index],Vector3(0,.51,.025),.70,0,"4d3035")
			# Fit the artwork inside the frame at its own proportions.
			var art:Texture2D=load(paths[index])
			var ratio:float=art.get_width()/float(art.get_height())
			var picture:=QuadMesh.new();picture.size=Vector2(minf(.66,.72*ratio),minf(.72,.66/ratio))
			var ink:=StandardMaterial3D.new();ink.albedo_texture=art;ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;ink.roughness=1
			poster.mesh_node(picture,Vector3(0,.02,.025),ink)
			poster.sign_text("LAST SHOW",Vector3(0,-.52,.025),.68,0,"563a3c")
	# Low cloth canopy only covers the main-tent side of the join. Its edges sit
	# inside the prepared opening; the real dressing tent canvas forms the exit.
	var canopy:=parts.box(Vector3(5.15,3.29,0),Vector3(10.3,.16,2.92),"423b3c")
	canopy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The narrow runner and broken brass borders gently bend left around the
	# authored dressing table at the right-hand mouth. No collision is added.
	var waypoints:=[Vector3(.15,0,0),Vector3(7.5,0,0),Vector3(9.2,0,-.22),Vector3(10.8,0,-.40),Vector3(12.15,0,-.12)]
	for segment in range(waypoints.size()-1):
		var a:Vector3=waypoints[segment];var b:Vector3=waypoints[segment+1]
		var delta:=b-a;var yaw:float=-atan2(delta.z,delta.x);var midpoint:Vector3=(a+b)*.5
		var runner:=parts.box(Vector3(midpoint.x,.045,midpoint.z),Vector3(delta.length()+.12,.028,1.16),"57404a")
		runner.rotation.y=yaw
		for edge in [-1,1]:
			var border:=parts.box(Vector3(midpoint.x,.064,midpoint.z),Vector3(delta.length(),.012,.025),"b79a62")
			border.rotation.y=yaw
			border.position+=Basis(Vector3.UP,yaw)*Vector3(0,0,edge*.53)
	# Repeated portal ribs stop below the untouched canvas and leave a clear,
	# continuous 2.9 m walking width between the added walls.
	for offset in [0.35,3.25,6.15,9.05,10.3]:
		# The last rib frames the dressing-tent canvas opening; no free posts.
		if offset>10.5:continue
		for side in [-1,1]:
			parts.rod(Vector3(offset,.06,side*1.47),Vector3(offset,3.15,side*1.47),.035,"75634c")
		parts.rod(Vector3(offset,3.15,-1.47),Vector3(offset,3.15,1.47),.035,"75634c")
	# Three visible pendants with real, restrained OmniLight3D fill.
	for offset in [2.2,6.0,10.0]:
		parts.rod(Vector3(offset,3.18,0),Vector3(offset,2.83,0),.012,"655a49")
		parts.cylinder(Vector3(offset,2.78,0),.20,.10,"5c5144",.2)
		var bulb_mesh:=parts.sphere(Vector3(offset,2.70,0),Vector3(.09,.09,.09),"f1dfbf")
		bulb_mesh.material_override=parts.material("f1dfbf",0,.5,1.2)
		var practical:=OmniLight3D.new();practical.name="PassagePractical"
		practical.position=Vector3(offset,2.62,0);practical.light_color=Color("f1dfbf")
		practical.light_energy=.72;practical.omni_range=5.1;practical.omni_attenuation=1.35
		practical.shadow_enabled=false;passage.add_child(practical)

func build_annex_roofs() -> void:
	for part in [[Vector3(game.layout.SERVICE_X,3.26,game.layout.SERVICE_START+4),Vector3(2.8,.12,8.2)],[Vector3(game.layout.CLINIC_CENTER.x-.1,3.46,game.layout.CLINIC_CENTER.z),Vector3(7.2,.12,6.2)]]:
		var roof:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=part[1]
		roof.mesh=box;roof.position=part[0]
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("687772");mat.roughness=.95
		roof.material_override=mat;add_child(roof)
		var body:=StaticBody3D.new();roof.add_child(body)
		var shape:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=box.size;shape.shape=bounds;body.add_child(shape)
