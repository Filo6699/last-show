extends "res://scripts/scene_parts.gd"
## Added scenery belongs to its own layer. The delivered layout stays intact.
var clinic_key:Node3D
var contract_paper:Node3D
var contract_target:StaticBody3D
var knife:Node3D
var locker:StaticBody3D
var clinic_chair:Vector3
var grain:NoiseTexture2D
var arena_details:Node3D

func setup(owner_game) -> void:
	game=owner_game;name="CircusSetDressing"
	make_grain();dress_floor();dress_canvas();arena();large_sets();dressing();service();clinic();outside()
	var presentation:=preload("res://scripts/scene_presentation.gd").new()
	add_child(presentation);presentation.setup(game)
	arena_details=preload("res://scripts/arena_details.gd").new()
	add_child(arena_details);arena_details.setup(game)
	var workrooms := preload("res://scripts/workroom_finish.gd").new()
	add_child(workrooms);workrooms.setup(game)
	batch()

func make_grain() -> void:
	grain=NoiseTexture2D.new();grain.width=256;grain.height=256;grain.seamless=true
	var noise:=FastNoiseLite.new();noise.seed=6119;noise.frequency=.034
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;noise.fractal_octaves=3
	grain.noise=noise

func floor_material(color:Color,kind:=0.0) -> ShaderMaterial:
	var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/shaders/set_surface.gdshader")
	mat.set_shader_parameter("base_color",color);mat.set_shader_parameter("grain",grain)
	mat.set_shader_parameter("surface_kind",kind)
	return mat

func dress_floor() -> void:
	game.location.stage_show.ring_mesh.material_override=floor_material(Color("4f393b"),1.0)
	for source in game.model.find_children("*","MeshInstance3D",true,false):
		if String(source.name)=="StoryTrunk":
			for surface in source.mesh.get_surface_count():
				var finish: Material=source.get_active_material(surface)
				if finish is StandardMaterial3D:
					finish=finish.duplicate();finish.disable_receive_shadows=true
					source.set_surface_override_material(surface,finish)
		# The long, shallow gallery barrier self-shadows into diagonal bands.
		# It still receives prop shadows and retains all source geometry/collision.
		if String(source.name)=="Cylinder_031":source.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(source.name) not in ["Circle","Circle_001","Plane"]:continue
		for index in source.mesh.get_surface_count():
			var mat:Material=source.get_active_material(index)
			if mat is StandardMaterial3D:
				# Blender's procedural wood_planks exported as untextured white.
				# Restore the same wood tone on both floor meshes, including Circle's
				# fourth surface, rather than bleaching the whole backstage annulus.
				var wood:bool=String(mat.resource_name).begins_with("wood_planks")
				var floor_tint: Color = Color("76634e") if wood or String(source.name)=="Circle_001" else mat.albedo_color
				# The source's pale painted floor stripe should read as worn paint,
				# not an overexposed spotlight wedge. Its geometry stays untouched.
				if String(mat.resource_name).begins_with("Aged_Paper"):floor_tint=floor_tint.darkened(.22)
				source.set_surface_override_material(index,floor_material(floor_tint,0.0 if wood or String(source.name)=="Circle_001" else 1.0))
		source.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(source.name)=="Circle":split_floor(source)

func arena() -> void:
	# A broad ring, gallery banners and rigging give the 100 m tent a coherent
	# scale. Storage sits at the edges, leaving the central performance floor free.
	for radius in [14.7,15.0]:ring(Vector3(0,.045,0),radius,.035,"b79b65")
	for x in [-13.5,13.5]:
		for z in [-10.5,12.5]:
			box(Vector3(x,.12,z),Vector3(.75,.24,.75),"252a2c",true,.55)
			for side in [-1,1]:rod(Vector3(x+side*.16,.2,z),Vector3(x+side*.16,9,z),.045,"3d4546",.65)
			for height in range(1,9):
				rod(Vector3(x-.16,height,z),Vector3(x+.16,height+.65,z),.018,"59605a",.5)
			rod(Vector3(x,9,z),Vector3(0,16,0),.022,"353d3f",.6)
	for index in 32:
		var angle:=TAU*index/32
		var at:=Vector3(sin(angle)*37.5,7.4,cos(angle)*37.5)
		var next:=Vector3(sin(angle+.19635)*37.5,7.4,cos(angle+.19635)*37.5)
		rod(at,next,.018,"514839")
		for j in 3:
			var center:=at.lerp(next,(j+.5)/3.0)
			var along:Vector3=(next-at).normalized()*.48
			var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([center-along,center+along,center+Vector3(0,-.75,0)])
			var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var flag:=mesh_node(mesh,Vector3.ZERO,material(["762f3c","9d814e","344d50"][(index+j)%3]),"GalleryPennant")
			flag.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	# Prop storage and stage preparation, with distinct silhouettes from each aisle.
	for entry in [[Vector3(22,0,-8),Vector3(1.5,1.1,1.1),.08],[Vector3(23.4,0,-8),Vector3(.9,.8,.8),-.12],[Vector3(22,1.1,-8),Vector3(1.0,.65,.8),.14],[Vector3(24.2,0,-6.4),Vector3(1.2,.8,1.0),.1],[Vector3(26,0,-7),Vector3(.8,1.2,.7),-.2]]:
		crate(entry[0],entry[1],entry[2])
	asset("rope_coil",Vector3(21,0,-5),.4)
	asset("wardrobe",Vector3(25,0,-11),-PI*.4)
	for i in 3:
		cylinder(Vector3(19+i*1.5,.65,-9.5),.47,1.3,"5a333a")
		for h in [.2,1.1]:ring(Vector3(19+i*1.5,h,-9.5),.48,.025,"a28b60")
		rod(Vector3(19+i*1.5,1.3,-9.5),Vector3(19+i*1.5,3.3,-9.5),.025,"bca776")
		var hoop:=ring(Vector3(19+i*1.5,2.6,-9.5),.65,.035,"b79759");hoop.rotation.x=PI/2
	point_light(Vector3(22,4,-7),"e9b873",1.1,10)
	# Training corner belongs to Bruno's conversation, away from the main aisle.
	training_rack()
	asset("potato_sacks",Vector3(-21.6,0,24.5),.3)
	asset("rope_coil",Vector3(-18,0,25.8),.5,1,false)
	box(Vector3(-17.5,.025,22),Vector3(7,.025,8),"323c39")
	table(Vector3(-19.5,0,18),2.3,.65)
	for i in 4:
		var bar:=rod(Vector3(-20.1+i*.38,.98,18),Vector3(-19.8+i*.38,.98,18),.035,"9d9d8c",.7)
		for end in [-1,1]:
			var plate:=cylinder(bar.position+Vector3(end*.18,0,0),.13,.07,"30353a",.7)
			plate.rotation.z=PI/2
	box(Vector3(-20.6,3.3,23),Vector3(.3,.24,3.8),"4b3930")
	rod(Vector3(-20.6,0,24),Vector3(-20.6,3.3,24),.1,"4b3930")
	rod(Vector3(-20.6,0,21.5),Vector3(-20.6,3.3,21.5),.1,"4b3930")
	rod(Vector3(-20.6,3.2,23),Vector3(-20.6,2.6,23),.025,"666759",.5)
	cylinder(Vector3(-20.6,1.9,23),.35,1.3,"533838")
	point_light(Vector3(-18,4,22),"e5b57b",1.3,10)
	# Old entrance ticket station: inspectable, rather than empty unused floor.
	var ticket_start:=get_child_count()
	table(Vector3(22,0,18),2,.8)
	for i in 4:box(Vector3(21.4+i*.35,.935,18),Vector3(.25,.018,.35),"c7b18a")
	box(Vector3(22.6,1.08,18),Vector3(.5,.28,.4),"3e4945",true,.6)
	plaque("LAST SHOW\nБИЛЕТЫ",Vector3(22,2.1,18.2),1.8,.9,PI)
	var tickets:=target("tickets",Vector3(22,1,17.6),Vector3(1.8,.5,.2),"Рассмотреть билеты")
	var ticket_meshes:Array[MeshInstance3D]=[]
	for node in get_children().slice(ticket_start):
		if node is MeshInstance3D:node.set_meta("dynamic_set",true);ticket_meshes.append(node)
	tickets.set_meta("outline_meshes",ticket_meshes)
	point_light(Vector3(22,3,17),"afc3bc",.8,8)
	for p in [Vector3(31,0,9),Vector3(29,0,11),Vector3(31,0,12.3),Vector3(-28,0,-13),Vector3(-26.5,0,-13)]:crate(p,Vector3(.85,.7,.7),p.x*.017)
	# Audience-facing banners and discreet practical bulbs around the gallery.
	for index in 10:
		var angle:=TAU*index/10+.1
		var at:=Vector3(sin(angle)*34,5.5,cos(angle)*34)
		if index in [0,5]:plaque("LAST\nSHOW",at,2.1,2.5,angle+PI)
		var lamp:=sphere(at+Vector3(0,2,0),Vector3(.16,.22,.16),"f5cc8d")
		lamp.material_override=material("f5cc8d",0,.6,1.1)
		point_light(at+Vector3(0,1.5,0),"c7b088",.38,10)
	# Ordinary scuffs, dropped programmes and paint marks break the featureless floor.
	for index in 45:
		var angle:=index*2.39996
		var radius:float=19+(index%9)*1.35
		var at:=Vector3(sin(angle)*radius,.028,cos(angle)*radius)
		var paper:=box(at,Vector3(.16,.006,.23),"9d947b")
		paper.rotation.y=angle
		for line in 3:box(at+Vector3(0,.004,(line-1)*.05),Vector3(.11,.001,.008),"554b40")
	# A small visible knife rests on the original trunk; the trunk itself stays put.
	knife=Node3D.new();knife.name="StoryKnife";knife.set_meta("dynamic_set",true);add_child(knife)
	var trunk:MeshInstance3D=game.model.find_child("StoryTrunk",true,false)
	var bounds:AABB=trunk.global_transform*trunk.get_aabb()
	var height:float=bounds.end.y+.027
	var handle:=box(Vector3(.38,height,.25),Vector3(.07,.05,.25),"3e3029")
	var blade:=box(Vector3(.38,height,.03),Vector3(.06,.025,.21),"b0b6ad",false,.8)
	handle.reparent(knife,true);blade.reparent(knife,true)
	var pickup:=target("knife",Vector3(.38,height+.04,.14),Vector3(.3,.13,.5),"Взять нож")
	pickup.set_meta("outline_meshes",[handle,blade]);knife.set_meta("target",pickup)

func training_rack() -> void:
	# One clean, supported bar replaces the imported rack's intersecting bars.
	var center := Vector3(-19.8, 0, 21.5)
	for side in [-1.0, 1.0]:
		var at := center + Vector3(-.25, 0, side * 1.05)
		box(at + Vector3(0, .07, 0), Vector3(.85, .14, .48), "35403c", true, .6, "TrainingRackFoot")
		box(at + Vector3(0, .69, 0), Vector3(.10, 1.25, .10), "59615a", true, .65, "TrainingRackPost")
		box(at + Vector3(.12, 1.28, 0), Vector3(.34, .07, .10), "8b9184", false, .7, "TrainingRackCradle")
	var bar := rod(center + Vector3(-.05, 1.36, -1.65), center + Vector3(-.05, 1.36, 1.65), .035, "a1a597", .8)
	bar.name = "SingleTrainingBar"
	for side in [-1.0, 1.0]:
		for plate_index in 3:
			var plate := cylinder(center + Vector3(-.05, 1.36, side * (1.21 + plate_index * .11)), .32, .10, "303b3a", .7, 20)
			plate.rotation.x = PI / 2
			plate.name = "TrainingPlate"
		var collar := cylinder(center + Vector3(-.05, 1.36, side * 1.56), .065, .06, "c0b78e", .8, 12)
		collar.rotation.x = PI / 2

func dressing() -> void:
	# The authored bed, wardrobe, two tables and standing mirror remain untouched.
	box(Vector3(-48,.027,39.5),Vector3(5.5,.025,4.8),"633442")
	for side in [-1,1]:
		box(Vector3(-48+side*2.5,.042,39.5),Vector3(.07,.006,4.4),"b29a68")
		box(Vector3(-48,.042,39.5+side*2.15),Vector3(5,.006,.07),"b29a68")
	var at:=Vector3(-54,0,35.5)
	var television_start:=get_child_count()
	table(at,1.6,.75)
	box(at+Vector3(0,1.3,0),Vector3(1.28,.78,.58),"573e31",true)
	box(at+Vector3(-.12,1.33,.31),Vector3(.86,.57,.025),"182a29")
	for y in range(6):box(at+Vector3(.48,1.13+y*.065,.31),Vector3(.12,.018,.015),"827456")
	for y in [1.16,1.48]:
		var dial:=cylinder(at+Vector3(.48,y,.34),.055,.025,"2a2b29",.3);dial.rotation.x=PI/2
	rod(at+Vector3(-.12,1.72,0),at+Vector3(-.52,2.25,0),.012,"929b91",.7)
	rod(at+Vector3(.12,1.72,0),at+Vector3(.55,2.15,0),.012,"929b91",.7)
	sign_text("ЭФИР ОКОНЧЕН",at+Vector3(-.12,1.33,.33),.31,0,"638d7c")
	var television:=target("television",at+Vector3(0,1.3,.4),Vector3(1.1,.65,.16),"Посмотреть телевизор")
	var tv_meshes:Array[MeshInstance3D]=[]
	for node in get_children().slice(television_start):
		if node is MeshInstance3D:node.set_meta("dynamic_set",true);tv_meshes.append(node)
	television.set_meta("outline_meshes",tv_meshes)
	rod(Vector3(-52.8,0,46),Vector3(-52.8,2.5,46),.035,"665c49",.4)
	rod(Vector3(-50.8,0,46),Vector3(-50.8,2.5,46),.035,"665c49",.4)
	rod(Vector3(-52.8,2.5,46),Vector3(-50.8,2.5,46),.035,"665c49",.4)
	for index in 4:
		var coat:=box(Vector3(-52.55+index*.46,1.65,46),Vector3(.35,1.45,.16),["583c40","3e4c4e","6c6552","533e4d"][index])
		coat.rotation.z=(index-1.5)*.04
	for i in 3:
		plaque(["НОВЫЙ СЕЗОН","АРТИСТЫ ЦИРКА","ВЕЧЕРОМ — АНШЛАГ"][i],Vector3(-54.5+i*1.1,2.4,33.9),.9,1.1,.2)
	point_light(Vector3(-53,3.5,36),"e1b98b",.7,7)

func service() -> void:
	var x:float=game.layout.SERVICE_X;var z:float=game.layout.SERVICE_START
	plaque("ТОЛЬКО ДЛЯ\nПЕРСОНАЛА",Vector3(x,2.9,z-.18),1.7,.6,PI)
	for side in [-1,1]:
		for offset in [2.5,5.8]:
			rod(Vector3(x+side*1.28,.25,z+offset),Vector3(x+side*1.28,2.8,z+offset),.04,"4f6563",.6)
	for offset in [1.4,4.4,6.8]:
		box(Vector3(x+.98,.025,z+offset),Vector3(.23,.018,.42),"6e6551")
		rod(Vector3(x+1.1,.06,z+offset),Vector3(x+.8,.06,z+offset+.3),.025,"90988d",.7)
	box(Vector3(x-1.1,1.5,z+3.8),Vector3(.32,.7,.5),"485653",true,.5)
	plaque("220 В",Vector3(x-.92,1.6,z+3.8),.35,.22,PI/2)
	for offset in [2.5,5.4]:
		box(Vector3(x,3.1,z+offset),Vector3(2.5,.08,.09),"394943",false,.5)

func clinic() -> void:
	var c:Vector3=game.layout.CLINIC_CENTER
	clinic_chair=c+Vector3(.9,0,1.4)
	var at:=clinic_chair
	cylinder(at+Vector3(0,.15,0),.45,.22,"74847d",.7)
	cylinder(at+Vector3(0,.48,0),.12,.6,"a1aaa0",.75)
	box(at+Vector3(0,.8,0),Vector3(.85,.2,1),"405e56",true)
	var back:=box(at+Vector3(0,1.35,.55),Vector3(.85,1.1,.18),"405e56");back.rotation.x=-.14
	box(at+Vector3(0,1.97,.63),Vector3(.57,.32,.16),"84948b")
	for side in [-1,1]:
		rod(at+Vector3(side*.5,.6,-.15),at+Vector3(side*.5,1,-.15),.035,"a1aaa0",.7)
		box(at+Vector3(side*.5,1,-.15),Vector3(.16,.08,.8),"5d756b")
		box(at+Vector3(side*.37,.85,-.15),Vector3(.12,.07,.9),"87724f")
	# Tables along the side wall leave the entire main approach unobstructed.
	table(c+Vector3(-2.6,0,-.8),1.0,1.8,"86978d")
	for i in 4:
		rod(c+Vector3(-2.9+i*.16,.94,-1.25),c+Vector3(-2.9+i*.16,.94,-.75),.015,"b7bfb1",.85)
	for i in 3:
		cylinder(c+Vector3(-2.9+i*.22,1.04,-.2),.055,.23,"a8c2aa")
	contract_paper=box(c+Vector3(-2.6,.929,-.65),Vector3(.43,.012,.58),"d4ceb1")
	contract_paper.set_meta("dynamic_set",true)
	var name_on_paper:=sign_text("RICHARD",c+Vector3(-2.6,.94,-.8),.26,0,"3a3a32")
	name_on_paper.rotation.x=-PI/2;name_on_paper.reparent(contract_paper,true)
	contract_target=target("contract",c+Vector3(-2.6,.97,-.65),Vector3(.5,.12,.65),"Рассмотреть документ")
	contract_target.set_meta("outline_meshes",[contract_paper])
	clinic_key=Node3D.new();clinic_key.set_meta("dynamic_set",true);add_child(clinic_key)
	var hoop:=ring(c+Vector3(-2.4,.965,-.4),.05,.013,"cbb873")
	var shaft:=rod(c+Vector3(-2.4,.965,-.45),c+Vector3(-2.4,.965,-.63),.014,"cbb873",.7)
	var tooth:=box(c+Vector3(-2.37,.965,-.61),Vector3(.05,.025,.055),"cbb873",false,.7)
	for obj in [hoop,shaft,tooth]:obj.reparent(clinic_key,true)
	var key_target:=target("roof_key",c+Vector3(-2.4,1,-.5),Vector3(.3,.15,.4),"Взять ключ от крыши")
	key_target.set_meta("outline_meshes",[hoop,shaft,tooth]);clinic_key.set_meta("target",key_target)
	# Tall clinic locker has an opening door and a real dark interior.
	var loc:=c+Vector3(-2.7,0,2.2)
	box(loc+Vector3(-.5,1.1,0),Vector3(.08,2.2,.8),"85948c",true,.35)
	box(loc+Vector3(.5,1.1,0),Vector3(.08,2.2,.8),"85948c",true,.35)
	box(loc+Vector3(0,1.1,.38),Vector3(1,2.2,.06),"34433d",true)
	for height in [.05,1,2.15]:box(loc+Vector3(0,height,0),Vector3(1,.06,.8),"a4b0a2")
	locker=target("locker",loc+Vector3(0,1.1,-.43),Vector3(.98,2.15,.1),"Открыть шкафчик",true)
	locker.set_meta("dynamic_set",true)
	var door:=BoxMesh.new();door.size=Vector3(.98,2.15,.08)
	var visual:=MeshInstance3D.new();visual.mesh=door;visual.material_override=material("8b9c90",.4)
	var hinge := Node3D.new(); hinge.name = "LockerHinge"
	hinge.position = Vector3(-.49, 0, 0)
	locker.add_child(hinge); hinge.add_child(visual)
	visual.position.x = .49
	locker.set_meta("hinge", hinge)
	for i in 5:
		var vent := box(loc+Vector3(0,1.6+i*.065,-.5),Vector3(.55,.018,.025),"3c5148")
		vent.reparent(hinge, true)
	point_light(c+Vector3(-1,2.9,1.2),"d2e1ce",.45,4)

func outside() -> void:
	# A skyline around the delivered tent is visible from the real rooftop.
	for entry in [[Vector3(69,0,-23),10.0,"73434b"],[Vector3(-64,0,-28),8.0,"665b43"],[Vector3(47,0,69),9.0,"3f5b5c"],[Vector3(-66,0,59),7.0,"655245"]]:
		var p:Vector3=entry[0];var r:float=entry[1]
		cylinder(p+Vector3(0,3,0),r,6,entry[2])
		var cone:=CylinderMesh.new();cone.bottom_radius=r*1.13;cone.top_radius=.12;cone.height=5;cone.radial_segments=16
		mesh_node(cone,p+Vector3(0,8.5,0),material(entry[2]))
		rod(p+Vector3(0,10.8,0),p+Vector3(0,13,0),.04,"807963")
		for i in 3:
			box(p+Vector3(-4+i*3,1,-r-.5),Vector3(2,2,1),"493a36")
		point_light(p+Vector3(0,4,-r-.5),"e5b875",.8,15)
	for x in [-76,77]:
		box(Vector3(x,1.8,18),Vector3(4,2.5,9),"535c50")
		for z in [15,21]:
			for side in [-1,1]:
				var wheel:=cylinder(Vector3(x+side*2,.7,z),.65,.16,"25292c");wheel.rotation.z=PI/2

func sync() -> void:
	arena_details.sync()
	# Lili's departure reveals the name and makes the scripted knife available.
	var available:bool=game.flags.get("richard_name_seen",false)
	var nameplate:Node3D=game.model.find_child("Trunk name",true,false)
	if nameplate:nameplate.visible=available
	knife.visible=available and not game.flags.get("knife",false)
	knife.get_meta("target").collision_layer=16 if knife.visible else 0
	clinic_key.visible=game.flags.get("contract_signed",false) and not game.flags.get("roof_key",false)
	clinic_key.get_meta("target").collision_layer=16 if clinic_key.visible else 0
	contract_paper.visible=game.phase=="contract"
	contract_target.collision_layer=16 if game.phase=="contract" else 0

func large_sets() -> void:
	# Full-size circus scenery gives each side of the arena a purpose and a
	# recognisable silhouette. All story aisles stay outside these footprints.
	wagon(Vector3(-25,0,7),"6e393f",true)
	wagon(Vector3(25,0,-16),"3b5556",false)
	# Ticket booth, with a clear counter facing the approach from the ring.
	var c:=Vector3(22,0,19.1)
	box(c+Vector3(0,.12,0),Vector3(5.5,.24,3.1),"493d32",true)
	for side in [-1,1]:
		box(c+Vector3(side*2.35,2.6,0),Vector3(.22,5.2,.25),"763844",true)
		box(c+Vector3(side*2.35,2.6,-.02),Vector3(.055,5,.29),"b59763")
	box(c+Vector3(0,4.65,0),Vector3(5.5,1,.4),"783b45")
	plaque("КАССА • LAST SHOW",c+Vector3(0,4.65,-.23),4.8,.75,PI)
	for index in 11:
		var shade:=box(c+Vector3(-2.5+index*.5,3.9,-.8),Vector3(.5,.1,1.7),"b69e72" if index%2==0 else "713744")
		shade.rotation.x=-.12
		var bulb:=sphere(c+Vector3(-2.5+index*.5,4.25,-.27),Vector3.ONE*.10,"ecd3a0")
		bulb.material_override=material("ecd3a0",0,.6,.8)
	for side in [-1,1]:
		for index in 3:
			var post:=c+Vector3(side*(3.2+index*.9),0,-2)
			cylinder(post+Vector3(0,.5,0),.045,1,"b29c6d",.7)
			cylinder(post+Vector3(0,.035,0),.18,.07,"4c4e45",.7)
			if index<2:rod(post+Vector3(0,.85,0),post+Vector3(side*.9,.85,0),.035,"692f40")
	point_light(c+Vector3(0,4,-2),"e7c28d",1.8,13)
	# High trapeze rig and a lowered safety net behind the ring.
	for x in [1.5,11.5]:
		for z in [23,28]:
			box(Vector3(x,.16,z),Vector3(.8,.32,.8),"45443c",true,.5)
			rod(Vector3(x,0,z),Vector3(x,11,z),.13,"465354",.6)
		rod(Vector3(x,11,23),Vector3(x,11,28),.11,"66716a",.6)
	rod(Vector3(1.5,11,25.5),Vector3(11.5,11,25.5),.13,"8a8973",.6)
	for x in [5.5,7.5]:rod(Vector3(x,11,25.5),Vector3(x,5.2,25.5),.035,"ab9870")
	rod(Vector3(5.5,5.2,25.5),Vector3(7.5,5.2,25.5),.055,"bda575")
	box(Vector3(6.5,.07,25.5),Vector3(8,.12,3.5),"40514b")
	for x in range(3,11):rod(Vector3(x,1.2,23.4),Vector3(x,.8,27.6),.013,"877e61")
	for i in 9:rod(Vector3(2.8,1,23.5+i*.5),Vector3(10.2,1,23.5+i*.5),.013,"877e61")
	point_light(Vector3(6.5,7,24),"9fbec5",1.8,16)
	# Rear curtain and upright lamps frame the original platform and roof door.
	for index in 20:
		var x:float=-10+index*1.0
		cylinder(Vector3(x,4.4,-17),.55,8.8,"502432" if index%2==0 else "66313e")
	rod(Vector3(-10.7,9,-17),Vector3(10.7,9,-17),.13,"8d7957",.55)
	plaque("ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ",Vector3(0,7.4,-16.35),13,1.4)
	for x in [-11,11]:
		box(Vector3(x,1.7,-15.5),Vector3(.9,3.4,.8),"343e40",true)
		for y in [1,2.4]:
			var grille:=ring(Vector3(x,y,-15.05),.3,.025,"81785f");grille.rotation.x=PI/2
	point_light(Vector3(0,6,-13),"bc875d",1.4,15)

func wagon(c:Vector3,color:String,open_back:bool) -> void:
	box(c+Vector3(0,.65,0),Vector3(3.7,.32,6.8),"443c32",true)
	box(c+Vector3(0,2.25,0),Vector3(3.5,2.9,6.3),color,true)
	for side in [-1,1]:
		for z in [-2.2,2.2]:
			var at:=c+Vector3(side*1.92,.72,z)
			var wheel:=cylinder(at,.72,.16,"292e2c",.2,20);wheel.rotation.z=PI/2
			var rim:=ring(at+Vector3(side*.1,0,0),.60,.045,"aa9160");rim.rotation.z=PI/2
			for index in 8:
				var a:=TAU*index/8
				rod(at+Vector3(side*.105,0,0),at+Vector3(side*.105,sin(a)*.58,cos(a)*.58),.025,"8b7754")
		for z in [-2.9,2.9]:box(c+Vector3(side*1.78,2.25,z),Vector3(.08,2.8,.12),"b59a68")
		for h in [1.05,3.55]:box(c+Vector3(side*1.78,h,0),Vector3(.08,.10,6.2),"b59a68")
		box(c+Vector3(side*1.8,2.5,-.5),Vector3(.055,1.1,1.5),"253f42")
		for offset in [-.8,0,.8]:box(c+Vector3(side*1.85,2.5,-.5+offset),Vector3(.06,1.15,.06),"c3b18b")
		plaque("LAST SHOW",c+Vector3(side*1.86,1.5,1.5),1.5,.45,side*PI/2)
	for index in 13:
		var a:float=PI*index/12
		box(c+Vector3(cos(a)*1.82,3.65+sin(a)*.7,0),Vector3(.35,.15,6.8),"69614e")
	if open_back:
		box(c+Vector3(0,2.3,-3.22),Vector3(1.25,2.5,.08),"312d2b")
		for i in 3:box(c+Vector3(0,.15+i*.17,-4.1+i*.25),Vector3(1.6,.3,.45),"756046",true)
		crate(c+Vector3(2.7,0,-1.7),Vector3(1.1,1,.8),.2)
		asset("clown_combat_boots",c+Vector3(2.7,1.0,-1.7),-.3,1,false)
	point_light(c+Vector3(-signf(c.x)*2.5,3.2,2.5),"e6c29b",1.6,15)

func split_floor(source:MeshInstance3D) -> void:
	# Compatibility lights are selected per draw object. The supplied 100 m
	# floor must have local render chunks to receive the local practicals.
	# Subdivision preserves its exact surface, source transform and collider.
	var pieces:={}
	for surface in source.mesh.get_surface_count():
		var arrays:=source.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var pending:Array=[]
		for index in range(0,indices.size(),3):pending.append([vertices[indices[index]],vertices[indices[index+1]],vertices[indices[index+2]],0])
		while not pending.is_empty():
			var tri:Array=pending.pop_back()
			var a:Vector3=tri[0];var b:Vector3=tri[1];var c:Vector3=tri[2]
			if maxf(a.distance_to(b),maxf(b.distance_to(c),c.distance_to(a)))>9 and tri[3]<6:
				var ab:Vector3=(a+b)*.5;var bc:Vector3=(b+c)*.5;var ca:Vector3=(c+a)*.5
				pending.append_array([[a,ab,ca,tri[3]+1],[ab,b,bc,tri[3]+1],[ca,bc,c,tri[3]+1],[ab,bc,ca,tri[3]+1]])
				continue
			var center:Vector3=source.to_global((a+b+c)/3)
			var key:=Vector3i(floori(center.x/10),surface,floori(center.z/10))
			if not pieces.has(key):
				var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builder.set_material(source.get_active_material(surface));pieces[key]=builder
			var normal:Vector3=(c-a).cross(b-a).normalized()
			for point in [a,b,c]:
				pieces[key].set_normal(normal);pieces[key].add_vertex(point)
	var container:=Node3D.new();container.name="LocalFloorLighting";add_child(container)
	for builder in pieces.values():
		var node:=MeshInstance3D.new();node.mesh=builder.commit();container.add_child(node)
		node.global_transform=source.global_transform
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	source.hide()

func point_light(at:Vector3,color:String,energy:float,reach:float) -> OmniLight3D:
	return super.point_light(at,color,energy,reach)

func dress_canvas() -> void:
	for source in game.model.find_children("*","MeshInstance3D",true,false):
		var extent:Vector3=(source.global_transform*source.get_aabb()).size
		var canvas:bool=String(source.name).contains("Tent") or String(source.name).contains("Шатер")
		if canvas and maxf(extent.x,extent.z)>12:
			source.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not canvas or maxf(extent.x,extent.z)<12 or extent.y<5:continue
		for index in source.mesh.get_surface_count():
			var original:Material=source.get_active_material(index)
			if not original is StandardMaterial3D:continue
			var cloth:=ShaderMaterial.new();cloth.shader=preload("res://assets/shaders/canvas_falloff.gdshader")
			cloth.set_shader_parameter("tint",original.albedo_color)
			cloth.set_shader_parameter("has_albedo",original.albedo_texture!=null)
			if original.albedo_texture:cloth.set_shader_parameter("albedo",original.albedo_texture)
			source.set_surface_override_material(index,cloth)
