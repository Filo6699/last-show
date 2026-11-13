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
var trunk_name_ru:Label3D
var trunk_lid:Node3D
var trunk_lid_tween:Tween
var trunk_open:=false
# Television in the dressing room: static, then a short broadcast.
const TV_STATIC_END:=1.3
const TV_CARD_END:=3.9
const TV_TOTAL:=4.4
var tv_origin:Vector3
var tv_idle_text:Label3D
var tv_static:MeshInstance3D
var tv_card:Node3D
var tv_light:OmniLight3D
var tv_noise:Image
var tv_noise_texture:ImageTexture
var tv_clock:=-1.0
var tv_next_noise:=0.0

func setup(owner_game) -> void:
	game=owner_game;name="CircusSetDressing"
	shrink_trunk()
	make_grain();dress_floor();dress_canvas();arena();large_sets();dressing();service();clinic();outside()
	russian_trunk_name()
	open_trunk_mesh()
	var presentation:=preload("res://scripts/scene_presentation.gd").new()
	add_child(presentation);presentation.setup(game)
	arena_details=preload("res://scripts/arena_details.gd").new()
	add_child(arena_details);arena_details.setup(game)
	var workrooms := preload("res://scripts/workroom_finish.gd").new()
	add_child(workrooms);workrooms.setup(game)
	batch()

# The supplied trunk stands 1.5 m tall and 2.1 m across: a crate, not a
# magician's trunk. Shrink it, mesh and collision alike, about its floor
# centre, so it still rests on the ring where the artist put it.
const TRUNK_SCALE := .75
func shrink_trunk() -> void:
	var trunk:=game.model.find_child("StoryTrunk",true,false) as MeshInstance3D
	if trunk==null:return
	var bounds:AABB=trunk.global_transform*trunk.get_aabb()
	var pivot:=Vector3(trunk.global_position.x,bounds.position.y,trunk.global_position.z)
	var shrink:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*TRUNK_SCALE),pivot-pivot*TRUNK_SCALE)
	trunk.global_transform=shrink*trunk.global_transform
	for body in game.model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh","")) not in ["StoryTrunk","Trunk name"]:continue
		for child in body.get_children():
			var shape:=child as CollisionShape3D
			if shape==null or not shape.shape is ConcavePolygonShape3D:continue
			var to_world:Transform3D=shape.global_transform
			var faces:=PackedVector3Array()
			for v in (shape.shape as ConcavePolygonShape3D).get_faces():faces.append(to_world.affine_inverse()*(shrink*(to_world*v)))
			var scaled:=ConcavePolygonShape3D.new();scaled.set_faces(faces);shape.shape=scaled

# Lili hides inside the trunk, so it needs a real opening. Cut the top cap off
# the supplied mesh, line the inside, and hinge a separate lid on the far side
# (away from the player's approach) that swings open when she jumps out.
const TRUNK_RIM := .48
const TRUNK_OPEN_ANGLE := -1.95
const TRUNK_TRAY := .44
func open_trunk_mesh() -> void:
	var trunk:=game.model.find_child("StoryTrunk",true,false) as MeshInstance3D
	if trunk==null:return
	var arrays:Array=trunk.mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var kept:=PackedInt32Array()
	for t in range(0,indices.size(),3):
		var top:=true
		for k in 3:
			if vertices[indices[t+k]].y<TRUNK_RIM-.005:top=false
		if top:continue
		kept.append(indices[t]);kept.append(indices[t+1]);kept.append(indices[t+2])
	arrays[Mesh.ARRAY_INDEX]=kept
	var finish:Material=trunk.get_active_material(0)
	var carved:=ArrayMesh.new();carved.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	trunk.mesh=carved;trunk.set_surface_override_material(0,finish)
	# Rim outline at the cut, sorted around the centre.
	var rim:Array[Vector2]=[]
	var seen:={}
	for v in vertices:
		if absf(v.y-TRUNK_RIM)>.005:continue
		var key:=Vector2(snappedf(v.x,.001),snappedf(v.z,.001))
		if seen.has(key):continue
		seen[key]=true;rim.append(key)
	rim.sort_custom(func(a:Vector2,b:Vector2)->bool:return atan2(a.y,a.x)<atan2(b.y,b.x))
	# Dark lining: inward-facing walls and a floor, slightly inside the shell.
	var lining:=SurfaceTool.new();lining.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner:=.94
	for i in rim.size():
		var a:Vector2=rim[i]*inner;var b:Vector2=rim[(i+1)%rim.size()]*inner
		var quad:=[Vector3(a.x,TRUNK_RIM,a.y),Vector3(b.x,TRUNK_RIM,b.y),Vector3(b.x,-.42,b.y),Vector3(a.x,-.42,a.y)]
		for idx in [0,2,1,0,3,2]:lining.add_vertex(quad[idx])
		lining.add_vertex(Vector3(0,-.42,0));lining.add_vertex(Vector3(a.x,-.42,a.y));lining.add_vertex(Vector3(b.x,-.42,b.y))
	lining.generate_normals()
	var inside:=MeshInstance3D.new();inside.name="TrunkLining";inside.mesh=lining.commit()
	var dark:=StandardMaterial3D.new();dark.albedo_color=Color("1d1512");dark.roughness=1;dark.cull_mode=BaseMaterial3D.CULL_DISABLED
	inside.material_override=dark;trunk.add_child(inside);inside.set_meta("dynamic_set",true)
	# False-bottom tray just under the rim: the knife rests here once it is open.
	var tray:=SurfaceTool.new();tray.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rim.size():
		var a:Vector2=rim[i]*.93;var b:Vector2=rim[(i+1)%rim.size()]*.93
		tray.add_vertex(Vector3(0,TRUNK_TRAY,0));tray.add_vertex(Vector3(b.x,TRUNK_TRAY,b.y));tray.add_vertex(Vector3(a.x,TRUNK_TRAY,a.y))
	tray.generate_normals()
	var tray_mesh:=MeshInstance3D.new();tray_mesh.name="TrunkTray";tray_mesh.mesh=tray.commit()
	var tray_material:=StandardMaterial3D.new();tray_material.albedo_color=Color("3a1f22");tray_material.roughness=.9;tray_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	tray_mesh.material_override=tray_material;trunk.add_child(tray_mesh);tray_mesh.set_meta("dynamic_set",true)
	# Lid: the cut cap rebuilt as a slab, hinged on the rim edge at local +X.
	var hinge_x:=-INF
	for p in rim:hinge_x=maxf(hinge_x,p.x)
	trunk_lid=Node3D.new();trunk_lid.name="TrunkLid";trunk.add_child(trunk_lid)
	trunk_lid.position=Vector3(hinge_x,TRUNK_RIM,0)
	var slab:=SurfaceTool.new();slab.begin(Mesh.PRIMITIVE_TRIANGLES)
	var thick:=.025
	for i in rim.size():
		var a:Vector2=rim[i]-Vector2(hinge_x,0);var b:Vector2=rim[(i+1)%rim.size()]-Vector2(hinge_x,0)
		var c:=Vector2(-hinge_x,0)
		slab.add_vertex(Vector3(c.x,thick,c.y));slab.add_vertex(Vector3(b.x,thick,b.y));slab.add_vertex(Vector3(a.x,thick,a.y))
		slab.add_vertex(Vector3(c.x,0,c.y));slab.add_vertex(Vector3(a.x,0,a.y));slab.add_vertex(Vector3(b.x,0,b.y))
		var side:=[Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(b.x,thick,b.y),Vector3(a.x,thick,a.y)]
		for idx in [0,1,2,0,2,3]:slab.add_vertex(side[idx])
	slab.generate_normals()
	var lid_mesh:=MeshInstance3D.new();lid_mesh.name="LidSlab";lid_mesh.mesh=slab.commit();lid_mesh.material_override=finish
	trunk_lid.add_child(lid_mesh);lid_mesh.set_meta("dynamic_set",true);trunk_lid.set_meta("dynamic_set",true)
	# The name is painted inside the lid, like a magician's trunk: it shows
	# once the lid stands open, upright, facing whoever looks into the trunk.
	if is_instance_valid(trunk_name_ru):
		trunk_name_ru.reparent(trunk_lid,false)
		trunk_name_ru.transform=Transform3D(Basis(Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,-1,0)),Vector3(-hinge_x,-.004,0))
		trunk_name_ru.double_sided=false

func set_trunk_open(value:bool,animate:=false) -> void:
	if trunk_lid==null:return
	if trunk_lid_tween and trunk_lid_tween.is_valid():trunk_lid_tween.kill()
	trunk_open=value
	var angle:=TRUNK_OPEN_ANGLE if value else 0.0
	if animate:
		trunk_lid_tween=create_tween()
		trunk_lid_tween.tween_property(trunk_lid,"rotation:z",angle,.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:trunk_lid.rotation.z=angle

# The supplied trunk lid spells the name in Latin letters as an extruded mesh.
# Keep that node (story code shows it and frames the camera on it) but stop
# drawing it, and lay the Russian name flat in its place, readable from above.
func russian_trunk_name() -> void:
	var source: MeshInstance3D = game.model.find_child("Trunk name", true, false)
	if source == null: return
	var bounds: AABB = source.global_transform * source.get_aabb()
	source.layers = 0
	source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label := Label3D.new()
	label.name = "TrunkNameRu"
	label.text = "РИЧАРД"
	label.font = preload("res://assets/fonts/DejaVuSerif.ttf")
	label.font_size = 64
	label.pixel_size = .5 / label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	label.modulate = Color("e4d3ad")
	label.outline_size = 6
	label.outline_modulate = Color("2a1d17")
	label.shaded = true
	# Same diagonal as the supplied lettering; text faces up.
	var up_on_lid := Vector3(-.707107, 0, -.707107)
	add_child(label)
	trunk_name_ru = label
	label.global_transform = Transform3D(Basis(up_on_lid.cross(Vector3.UP), up_on_lid, Vector3.UP), bounds.get_center() + Vector3(0, bounds.size.y * .5 + .004, 0))

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
		# The 200 m ground plane is coplanar (y=0) with the annex floors ("Clinic
		# floor", "Service floor"), so the two colours z-fight. Sink the visual-only
		# ground 2 cm; it has no collider, and every room floor then wins cleanly.
		if String(source.name)=="Plane":source.global_position.y-=.02

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
	# The three hoop drums stand shoulder to shoulder; one body covers the row.
	blocker(Vector3(20.5,.65,-9.5),Vector3(4.0,1.3,1.0))
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
	# Four separate dumbbells lie across the table top, each handle running
	# front to back with a clear gap to its neighbour; plates rest on the wood.
	for i in 4:
		var handle_x:=-20.1+i*.4
		var top:=.905+.1
		rod(Vector3(handle_x,top,17.8),Vector3(handle_x,top,18.2),.03,"9d9d8c",.7)
		for end in [-1,1]:
			var plate:=cylinder(Vector3(handle_x,top,18+end*.15),.1,.07,"30353a",.7)
			plate.rotation.x=PI/2
	# Bag, its two uprights and the hanging chain share one solid footprint.
	blocker(Vector3(-20.6,1.65,22.75),Vector3(.72,3.3,2.75))
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
		if index in [0,5]:
			plaque("LAST\nSHOW",at,2.1,2.5,angle+PI)
			# Banners hang from the canvas on two cables.
			for side in [-1,1]:hang_cable.call_deferred(at+Basis(Vector3.UP,angle+PI)*Vector3(side*.9,1.25,0))
		var lamp:=sphere(at+Vector3(0,2,0),Vector3(.16,.22,.16),"f5cc8d")
		lamp.material_override=material("f5cc8d",0,.6,1.1)
		hang_cable.call_deferred(at+Vector3(0,2.2,0))
		point_light(at+Vector3(0,1.5,0),"c7b088",.38,10)
	# The knife stands stuck point-down in the trunk's tray beside the painted
	# name the camera frames when Lili runs off, clear of the letters. Grip and
	# guard rise above the rim, flat side to the player's approach, under a
	# small spot.
	knife=Node3D.new();knife.name="StoryKnife";knife.set_meta("dynamic_set",true);add_child(knife)
	var trunk:MeshInstance3D=game.model.find_child("StoryTrunk",true,false)
	# Colours follow the artist's item drawing: black grip, steel guard and pommel.
	# Built along local +Z (pommel end); the guard sits at the origin.
	var handle:=box(Vector3(0,0,.11),Vector3(.06,.045,.24),"1e1d22")
	var blade:=box(Vector3(0,0,-.11),Vector3(.065,.02,.22),"c4c8d2",false,.85)
	var guard:=box(Vector3(0,0,-.008),Vector3(.13,.035,.024),"8e9099",false,.8)
	var pommel:=box(Vector3(0,0,.238),Vector3(.085,.045,.018),"8e9099",false,.8)
	for part in [handle,blade,guard,pommel]:part.reparent(knife,false)
	var tray:Vector3=trunk.to_global(Vector3(.12,TRUNK_TRAY,.32))
	var upright:=Basis(Vector3.UP,-PI/4)*Basis(Vector3.RIGHT,-PI/2+.2)
	knife.global_transform=Transform3D(upright.scaled_local(Vector3.ONE*1.2),tray+Vector3(0,.15,0))
	var glint:=SpotLight3D.new();glint.name="KnifeGlint";glint.light_color=Color("f2e6cf");glint.light_energy=4.0
	glint.spot_range=2.0;glint.spot_angle=14;glint.spot_attenuation=.5;glint.shadow_enabled=false
	knife.add_child(glint);glint.global_position=tray+Vector3(-.5,1.1,.5);glint.look_at(tray+Vector3(0,.2,0),Vector3.UP)
	# The pickup box wraps the grip and guard above the rim.
	var pickup:=target("knife",tray+Vector3(-.02,.27,.02),Vector3(.24,.36,.24),"Взять нож")
	pickup.set_meta("outline_meshes",[handle,blade,guard,pommel]);knife.set_meta("target",pickup)

func training_rack() -> void:
	# One clean, supported bar replaces the imported rack's intersecting bars.
	var center := Vector3(-19.8, 0, 21.5)
	for side in [-1.0, 1.0]:
		var at := center + Vector3(-.25, 0, side * 1.05)
		box(at + Vector3(0, .07, 0), Vector3(.85, .14, .48), "35403c", false, .6, "TrainingRackFoot")
		box(at + Vector3(0, .69, 0), Vector3(.10, 1.25, .10), "59615a", false, .65, "TrainingRackPost")
		box(at + Vector3(.12, 1.28, 0), Vector3(.34, .07, .10), "8b9184", false, .7, "TrainingRackCradle")
	# Feet, posts, bar and plates: the bar no longer lets the player walk between posts.
	blocker(center + Vector3(-.22, .85, 0), Vector3(.98, 1.7, 3.3))
	var bar := rod(center + Vector3(-.05, 1.36, -1.65), center + Vector3(-.05, 1.36, 1.65), .035, "a1a597", .8)
	bar.name = "SingleTrainingBar"
	# Three plates per side, stepping down in size with a clear gap between
	# them, so each reads as its own disc instead of one merged drum.
	for side in [-1.0, 1.0]:
		for plate_index in 3:
			var plate := cylinder(center + Vector3(-.05, 1.36, side * (1.19 + plate_index * .12)), .32 - plate_index * .05, .07, "303b3a", .7, 20)
			plate.rotation.x = PI / 2
			plate.name = "TrainingPlate"
		var collar := cylinder(center + Vector3(-.05, 1.36, side * 1.52), .065, .06, "c0b78e", .8, 12)
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
	tv_origin=at+Vector3(-.12,1.33,.31)
	box(tv_origin,Vector3(.86,.57,.025),"182a29")
	for y in range(6):box(at+Vector3(.48,1.13+y*.065,.31),Vector3(.12,.018,.015),"827456")
	for y in [1.16,1.48]:
		var dial:=cylinder(at+Vector3(.48,y,.34),.055,.025,"2a2b29",.3);dial.rotation.x=PI/2
	rod(at+Vector3(-.12,1.72,0),at+Vector3(-.52,2.25,0),.012,"929b91",.7)
	rod(at+Vector3(.12,1.72,0),at+Vector3(.55,2.15,0),.012,"929b91",.7)
	tv_idle_text=sign_text("ЭФИР ОКОНЧЕН",at+Vector3(-.12,1.33,.33),.31,0,"638d7c")
	var television:=target("television",at+Vector3(0,1.3,.4),Vector3(1.1,.65,.16),"Посмотреть телевизор")
	var tv_meshes:Array[MeshInstance3D]=[]
	for node in get_children().slice(television_start):
		if node is MeshInstance3D:node.set_meta("dynamic_set",true);tv_meshes.append(node)
	television.set_meta("outline_meshes",tv_meshes)
	build_television_screen()
	# The supplied teal door mat at the passage mouth sits under the end of the
	# passage runner, a second rug overlapping the first right in the doorway.
	# The runner already marks the way in; drop the mat and its 2 cm collider.
	var door_mat:=game.model.find_child("Plane_008",true,false) as MeshInstance3D
	if door_mat:door_mat.hide()
	for body in game.model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh",""))=="Plane_008":body.collision_layer=0
	# The supplied costume stand carries about 100k vertices (tester: 20 fps next to
	# it on a phone). Hide it with its eight garments and drop every collider.
	var costume_stand:=game.model.find_child("Dressing Stand",true,false) as Node3D
	if costume_stand:
		costume_stand.hide()
		for part in costume_stand.find_children("*","MeshInstance3D",true,false):part.hide()
	for body in game.model.get_node("GeometryCollisions").get_children():
		var source:=String(body.get_meta("source_mesh",""))
		if source=="Dressing Stand" or source.begins_with("Mesh_0"):body.collision_layer=0
	# The candle stubs on both vanity tables are a heavy surface of their own.
	for table_name in ["vanity_table","vanity_table_002"]:
		var vanity:=game.model.find_child(table_name,true,false) as MeshInstance3D
		if vanity:strip_candles(vanity)
	# The tent's three lantern mounts were authored for a lower ceiling and hung
	# 2-4 m under the canvas, one of them over the bed. Run each up on a cable.
	for lantern in game.model.find_children("Lamp ceiling mount*","MeshInstance3D",true,false):
		var bounds:AABB=lantern.global_transform*lantern.get_aabb()
		var top:=Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)
		if lantern.visible and Vector2(top.x+48.14,top.z-40.12).length()<10:hang_cable.call_deferred(top)
	blocker(Vector3(-51.8,1.25,45.95),Vector3(2.2,2.5,.5))
	rod(Vector3(-52.8,0,46),Vector3(-52.8,2.5,46),.035,"665c49",.4)
	rod(Vector3(-50.8,0,46),Vector3(-50.8,2.5,46),.035,"665c49",.4)
	rod(Vector3(-52.8,2.5,46),Vector3(-50.8,2.5,46),.035,"665c49",.4)
	for index in 4:
		var coat:=box(Vector3(-52.55+index*.46,1.65,46),Vector3(.35,1.45,.16),["583c40","3e4c4e","6c6552","533e4d"][index])
		coat.rotation.z=(index-1.5)*.04
	for i in 3:
		plaque(["НОВЫЙ СЕЗОН","АРТИСТЫ ЦИРКА","СЕГОДНЯ АНШЛАГ"][i],Vector3(-54.5+i*1.1,2.4,33.9),.9,1.1,.2)
	point_light(Vector3(-53,3.5,36),"e1b98b",.7,7)

func build_television_screen() -> void:
	tv_noise=Image.create(40,26,false,Image.FORMAT_L8)
	tv_noise_texture=ImageTexture.create_from_image(tv_noise)
	var screen_size:=Vector2(.84,.55)
	var quad:=QuadMesh.new();quad.size=screen_size
	var noise_material:=StandardMaterial3D.new()
	noise_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	noise_material.albedo_texture=tv_noise_texture;noise_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tv_static=mesh_node(quad,tv_origin+Vector3(0,0,.018),noise_material,"TvStatic")
	tv_static.set_meta("dynamic_set",true);tv_static.visible=false
	tv_card=Node3D.new();tv_card.name="TvCard";tv_card.visible=false;add_child(tv_card)
	var card_material:=StandardMaterial3D.new();card_material.albedo_color=Color("16202e")
	card_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var red_material:=StandardMaterial3D.new();red_material.albedo_color=Color("b3262d")
	red_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var back:=MeshInstance3D.new();back.mesh=quad;back.material_override=card_material
	back.position=tv_origin+Vector3(0,0,.022);tv_card.add_child(back)
	var band_mesh:=QuadMesh.new();band_mesh.size=Vector2(.84,.11)
	var band:=MeshInstance3D.new();band.mesh=band_mesh;band.material_override=red_material
	band.position=tv_origin+Vector3(0,.22,.024);tv_card.add_child(band)
	for line in [["СРОЧНО",.62,Vector3(0,.22,.03),"f4f0e6"],["ПРОПАЛ\nПАЦИЕНТ",.78,Vector3(0,.0,.03),"f4f0e6"],["ВИДЕЛИ ЕГО?",.74,Vector3(0,-.21,.03),"f0cf6a"]]:
		var label:=sign_text(line[0],tv_origin+line[2],line[1],0,line[3])
		label.shaded=false;label.outline_size=0
		label.reparent(tv_card,false);label.position=tv_origin+line[2]
	tv_light=point_light(tv_origin+Vector3(0,0,.9),"9fc2ff",0.0,3.5)

func play_television() -> void:
	tv_clock=0.0;tv_next_noise=0.0
	if tv_idle_text:tv_idle_text.visible=false
	tv_light.light_energy=.6

func _process(delta:float) -> void:
	if tv_clock<0.0:return
	tv_clock+=delta
	if tv_clock>=TV_TOTAL:
		tv_clock=-1.0;tv_static.visible=false;tv_card.visible=false;tv_light.light_energy=0.0
		if tv_idle_text:tv_idle_text.visible=true
		return
	# The picture stutters on: a short black gap, then snow, then the card.
	var in_card:=tv_clock>=TV_STATIC_END and tv_clock<TV_CARD_END
	var gap:=tv_clock<.12 or (tv_clock>.26 and tv_clock<.34) or (in_card and tv_clock<TV_STATIC_END+.12)
	tv_card.visible=in_card and not gap
	tv_static.visible=not in_card and not gap
	tv_light.light_energy=0.0 if gap else (.5+randf()*.3 if not in_card else .35)
	if tv_static.visible and tv_clock>=tv_next_noise:
		tv_next_noise=tv_clock+.05
		for y in tv_noise.get_height():
			for x in tv_noise.get_width():tv_noise.set_pixel(x,y,Color.from_hsv(0,0,randf()*.85+.1))
		tv_noise_texture.update(tv_noise)

func strip_candles(vanity:MeshInstance3D) -> void:
	var source:=vanity.mesh as ArrayMesh
	if source==null:return
	var stripped:=ArrayMesh.new()
	for surface in source.get_surface_count():
		var material:=source.surface_get_material(surface)
		var label:=material.resource_name if material else ""
		if label.begins_with("Dirty_candle_wax") or label.begins_with("Soot_black"):continue
		stripped.add_surface_from_arrays(source.surface_get_primitive_type(surface),source.surface_get_arrays(surface))
		stripped.surface_set_material(stripped.get_surface_count()-1,material)
	vanity.mesh=stripped

func service() -> void:
	var x:float=game.layout.SERVICE_X;var z:float=game.layout.SERVICE_START
	# One line, so the sign fits between the door head and the vestibule ceiling.
	plaque("ТОЛЬКО ДЛЯ ПЕРСОНАЛА",Vector3(x,2.84,z-.18),2.1,.3,PI)
	# The corridor floor overlaps the clinic floor by 20 cm in the doorway, both
	# at y=0. Sink the walnut 1 cm (visual only) so the clinic floor wins there.
	var corridor_floor:Node3D=game.model.find_child("Service floor",true,false)
	if corridor_floor:corridor_floor.global_position.y-=.01
	var braces:StaticBody3D=null
	for side in [-1,1]:
		for offset in [2.5,5.8]:
			rod(Vector3(x+side*1.28,.25,z+offset),Vector3(x+side*1.28,2.8,z+offset),.04,"4f6563",.6)
			braces=blocker(Vector3(x+side*1.3,1.4,z+offset),Vector3(.14,2.8,.14),0.0,braces)
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
	# Everything on the treatment table rests on its top (y .905 above c).
	# Far end: a rimmed steel instrument tray with a scalpel and forceps.
	var top:=.905
	var tray_at:=c+Vector3(-2.72,top+.006,-1.38)
	box(tray_at,Vector3(.36,.012,.5),"9aa49f",false,.75)
	for side in [-1.0,1.0]:
		box(tray_at+Vector3(side*.174,.022,0),Vector3(.012,.04,.5),"b4bcb6",false,.8)
		box(tray_at+Vector3(0,.022,side*.244),Vector3(.36,.04,.012),"b4bcb6",false,.8)
	rod(tray_at+Vector3(-.07,.016,.17),tray_at+Vector3(-.07,.016,-.05),.007,"c9cfca",.85)
	var blade:=box(tray_at+Vector3(-.07,.012,-.09),Vector3(.016,.003,.08),"e2e6e3",false,.9)
	blade.rotation.y=.08
	for side in [-1.0,1.0]:
		rod(tray_at+Vector3(.06,.012,.16),tray_at+Vector3(.06+side*.025,.012,-.12),.005,"c9cfca",.85)
	# Near end: three small amber medicine bottles with dark caps.
	for i in 3:
		var bottle_at:=c+Vector3(-2.95+i*.11,top,-.08-(i%2)*.07)
		cylinder(bottle_at+Vector3(0,.06,0),.035,.12,"7a4a22",.1,14)
		cylinder(bottle_at+Vector3(0,.135,0),.022,.03,"25211d",.0,12)
	contract_paper=box(c+Vector3(-2.6,.929,-.65),Vector3(.43,.012,.58),"d4ceb1")
	contract_paper.set_meta("dynamic_set",true)
	var name_on_paper:=sign_text("РИЧАРД",c+Vector3(-2.6,.94,-.8),.26,0,"3a3a32")
	name_on_paper.rotation.x=-PI/2;name_on_paper.reparent(contract_paper,true)
	contract_target=target("contract",c+Vector3(-2.6,.97,-.65),Vector3(.5,.12,.65),"Рассмотреть документ")
	contract_target.set_meta("outline_meshes",[contract_paper])
	clinic_key=Node3D.new();clinic_key.set_meta("dynamic_set",true);add_child(clinic_key)
	# Pale steel, as in the artist's key drawing. Walter leaves it on a folded
	# white cloth beside the contract, where it reads at a glance.
	var cloth_y:=.905+.012
	var cloth:=box(c+Vector3(-2.33,.905+.006,-.3),Vector3(.2,.012,.3),"dcd8cb")
	cloth.reparent(clinic_key,true)
	var hoop:=ring(c+Vector3(-2.33,cloth_y+.012,-.2),.04,.011,"cfc8b4")
	var shaft:=rod(c+Vector3(-2.33,cloth_y+.012,-.24),c+Vector3(-2.33,cloth_y+.012,-.42),.011,"cfc8b4",.3)
	var tooth:=box(c+Vector3(-2.305,cloth_y+.012,-.4),Vector3(.04,.02,.045),"cfc8b4",false,.3)
	for obj in [hoop,shaft,tooth]:obj.reparent(clinic_key,true)
	var key_target:=target("roof_key",c+Vector3(-2.33,.98,-.3),Vector3(.3,.15,.42),"Взять ключ от крыши")
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
	if trunk_name_ru:trunk_name_ru.visible=available
	# Open from the moment Lili jumps out; the reveal itself animates the lid.
	var lili_out:bool=game.flags.get("lili_visible",false) or game.phase not in ["intro","news","to_dressing","mirror","elsa_dressing","to_hall","lili"]
	if lili_out!=trunk_open and not (trunk_lid_tween and trunk_lid_tween.is_valid()):set_trunk_open(lili_out)
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
	# The lowered net hangs at waist height: it is a barrier, not a walkway.
	blocker(Vector3(6.5,.6,25.5),Vector3(7.6,1.2,4.4))
	for x in range(3,11):rod(Vector3(x,1.2,23.4),Vector3(x,.8,27.6),.013,"877e61")
	for i in 9:rod(Vector3(2.8,1,23.5+i*.5),Vector3(10.2,1,23.5+i*.5),.013,"877e61")
	point_light(Vector3(6.5,7,24),"9fbec5",1.8,16)
	# Rear curtain and upright lamps frame the original platform and roof door.
	for index in 20:
		var x:float=-10+index*1.0
		cylinder(Vector3(x,4.4,-17),.55,8.8,"502432" if index%2==0 else "66313e")
	# Heavy pleated fabric is one continuous wall. Its west end stays open so the
	# backstage strip behind it (x -12..-8, z -17..-24) is reached around the edge.
	blocker(Vector3(-.5,4.4,-17),Vector3(20.1,8.8,1.1))
	rod(Vector3(-10.7,9,-17),Vector3(10.7,9,-17),.13,"8d7957",.55)
	plaque("ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ",Vector3(0,7.4,-16.35),13,1.4)
	for x in [-11,11]:
		box(Vector3(x,1.7,-15.5),Vector3(.9,3.4,.8),"343e40",true)
		for y in [1,2.4]:
			var grille:=ring(Vector3(x,y,-15.05),.3,.025,"81785f");grille.rotation.x=PI/2
	point_light(Vector3(0,6,-13),"bc875d",1.4,15)

func hang_cable(top:Vector3) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(game):return
	var query:=PhysicsRayQueryParameters3D.create(top,top+Vector3(0,40,0),1,[game.player.get_rid()])
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():rod(top,hit.position,.01,"25262a")

func wagon(c:Vector3,color:String,open_back:bool) -> void:
	box(c+Vector3(0,.65,0),Vector3(3.7,.32,6.8),"443c32")
	# Chassis plus the outboard wheels and rims.
	blocker(c+Vector3(0,.72,0),Vector3(4.3,1.44,6.8))
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
