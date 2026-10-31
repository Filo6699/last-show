extends Node3D
## Fixed theatre practicals, cool distance haze and readable pools along the story route.
## Compatibility renderer: ordinary fog and a small number of shadowed lights.
var game
var lamps: Array[OmniLight3D] = []
var show_spots: Array[SpotLight3D] = []
var fixed_spots:Array[SpotLight3D]=[]
var show_mode := -1
var show_fade: Tween
var fade_paused := false

func setup(owner_game) -> void:
	game=owner_game
	configure_environment()
	# These ten anchors also serve the existing rigging/flicker sound cues.
	var practicals := [
		[Vector3(0,7,0),"c8c8bf",.50,38.0],
		[Vector3(-12,3.8,29),"ffbc72",.75,6.5],
		[Vector3(game.layout.SERVICE_X,2.74,40.8),"ffc181",.85,6.0],
		[Vector3(-41.3,2.8,36.6),"ffd29a",1.15,6.0],
		[Vector3(-53,2.9,44),"d59b66",.60,5.5],
		[Vector3(-44,3.4,41),"a6b8c1",.45,7.0],
		[Vector3(-33,2.65,39.5),"f2ac61",.90,4.7],
		[Vector3(game.layout.SERVICE_X,2.8,game.layout.SERVICE_START+2),"88b3b4",.75,4.7],
		[Vector3(game.layout.SERVICE_X,2.8,game.layout.SERVICE_START+6),"81a5ad",.65,4.5],
		[Vector3(game.layout.CLINIC_CENTER.x,2.95,game.layout.CLINIC_CENTER.z),"e2e8df",1.05,6.5]
	]
	for i in practicals.size():
		var data: Array=practicals[i]
		var light:=OmniLight3D.new();light.name="Practical"+str(i)
		light.position=data[0];light.light_color=Color(data[1]);light.light_energy=data[2]*(1.25 if i in [1,2,3,4,6] else 1.0)
		light.set_meta("rest_energy",light.light_energy);light.omni_range=data[3];light.omni_attenuation=1.6
		light.shadow_enabled=false
		light.shadow_bias=.04;light.shadow_normal_bias=.25
		add_child(light);lamps.append(light)
		# Backstage sconces light Mordecai's spot, and the passage already has its
		# own pendant at the dressing curtain; these pools have no visible fitting.
		if i in [1,6]:continue
		# A visible shade/bulb anchors every local pool to the set.
		var fitting:=pendant(data[0],light.light_color)
		if i==2:
			wire(data[0]+Vector3(0,.23,0),Vector3(data[0].x,3.2,data[0].z))
		elif i<6:
			hang.call_deferred(data[0]+Vector3(0,.23,0),fitting)
		else:
			wire(data[0]+Vector3(0,.23,0),Vector3(data[0].x,3.3 if i==6 else 3.4,data[0].z))
	# Warm crossed keys pick out the ring instead of lighting the entire tent evenly.
	spot("RingAmber",Vector3(-9,10,-5),Vector3(1,0,2),"f5dfbf",3.6,38,48,true,true)
	spot("RingIvory",Vector3(9,11,6),Vector3(-2,0,-1),"ebe3d0",1.8,38,55,false,true)
	spot("RingCoolRim",Vector3(2,15,-3),Vector3(0,1,6),"b4c5d0",1.4,50,68,false,false)
	spot("StageKey",Vector3(0,7,-3.5),Vector3(0,.4,-6.2),"f5ddbb",3.4,23,52,true,true)
	spot("BackstageKey",Vector3(-12,7,26),Vector3(-12,1,29),"ead2b4",2.1,22,42,true,false)
	# Grazing fills reveal the stepped gallery rather than whitening every wall.
	spot("GalleryEast",Vector3(4,11,1),Vector3(34,4,16),"bac5ce",1.25,56,58,false,false)
	spot("GalleryWest",Vector3(-5,12,0),Vector3(-32,4,16),"c9bca9",1.10,56,58,false,false)
	spot("ServiceApproach",Vector3(game.layout.SERVICE_X,6,game.layout.SERVICE_START-5),Vector3(game.layout.SERVICE_X,0,game.layout.SERVICE_START-2),"e6d4b9",1.8,21,60,false,false)
	spot("TrainingKey",Vector3(-10,8,16),Vector3(-18,1,23),"e8d4b7",2.0,25,58,true,false)
	spot("StorageKey",Vector3(18.5,4.8,-4.3),Vector3(24,1,-9),"ead6b9",2.5,22,54,true,false)
	spot("DressingKey",Vector3(-49,5.8,35),Vector3(-44,1.3,38),"eed7b8",1.1,18,70,true,false)
	spot("ClinicTask",game.layout.CLINIC_CENTER+Vector3(0,2.8,0),game.layout.CLINIC_CENTER+Vector3(.9,.7,1.4),"e3e8dd",1.35,7,68,true,false,true,false)
	# The distant entrance reads as a cold silhouette, with the roof falling into haze.
	spot("EntranceBlue",Vector3(47,5,20),Vector3(31,0,13),"b4c9d3",2.6,38,50,false,false)
	spot("CurtainUplight",Vector3(0,1,-7.8),Vector3(0,12,-19),"b37b54",.85,32,45,false,false,false)
	# No vanity bulbs: they hung on the oval mirror frames, and mirrors.gd strips
	# the glass and frame from every vanity (the story mirror is the standing one),
	# so bulbs placed there would float against the canvas.
	add_dust(Vector3(0,3,0),Vector3(9,2.5,8))
	add_dust(Vector3(-49,2,38),Vector3(4,1.4,3))

func configure_environment() -> void:
	var environment: Environment=game.get_node("World/WorldEnvironment").environment
	environment.background_color=Color(.009,.014,.023)
	environment.ambient_light_color=Color("b4bdc5")
	environment.ambient_light_energy=.24
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure=1.0
	environment.fog_enabled=true
	environment.fog_mode=Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin=38
	environment.fog_depth_end=108
	environment.fog_light_color=Color("293844")
	environment.fog_light_energy=.38
	environment.fog_sun_scatter=0
	environment.fog_sky_affect=1
	environment.adjustment_enabled=true
	environment.adjustment_saturation=.94
	environment.adjustment_contrast=1.0
	# The old global sun cast enormous black stripes through an indoor tent.
	var sun:DirectionalLight3D=game.get_node("World/LayoutLight")
	sun.light_energy=0;sun.shadow_enabled=false

func spot(id: String, at: Vector3, target: Vector3, color: String, energy: float, reach: float, angle: float, shadows: bool, performance: bool, suspended: bool = true, visible_fixture: bool = true) -> void:
	var light:=SpotLight3D.new();light.name=id
	add_child(light);light.position=at;light.look_at(target)
	light.light_color=Color(color);light.light_energy=energy
	light.set_meta("show_energy",energy)
	light.spot_range=reach;light.spot_angle=angle
	light.spot_angle_attenuation=1.65;light.spot_attenuation=.65
	light.shadow_enabled=shadows;light.shadow_bias=.04;light.shadow_normal_bias=.65
	# Back faces keep the nearby keys from striping the faceted character meshes.
	light.shadow_reverse_cull_face=id in ["BackstageKey","TrainingKey"]
	light.shadow_blur=10.0 if id=="ClinicTask" else 3.0
	light.shadow_opacity=.28 if id=="ClinicTask" else (.65 if id=="TrainingKey" else (.60 if id=="DressingKey" else .90))
	fixed_spots.append(light)
	if performance:show_spots.append(light)
	if id in ["RingAmber","RingIvory"]: add_shaft(light,target)
	# ClinicTask shares the already visible ceiling pendant; no second floor stand.
	if not visible_fixture: return
	# Black can, glowing lens and suspension wire; fixtures do not follow the camera.
	var fixture:=Node3D.new();fixture.transform=light.transform;add_child(fixture)
	if id=="StorageKey":fixture.scale=Vector3.ONE*.65
	var shell:=MeshInstance3D.new();var can:=CylinderMesh.new()
	can.top_radius=.20;can.bottom_radius=.26;can.height=.50;can.radial_segments=12
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color("1d2025");metal.metallic=.6;metal.roughness=.72
	can.material=metal;shell.mesh=can;shell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;shell.rotation.x=PI/2;fixture.add_child(shell)
	var lens:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=.19;disc.bottom_radius=.19;disc.height=.025;disc.radial_segments=12
	disc.material=glowing(light.light_color,1.5);lens.mesh=disc;lens.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;lens.rotation.x=PI/2;lens.position.z=-.26
	fixture.add_child(lens)
	if suspended:wire(at,Vector3(at.x,20,at.z))
	else:
		var stand:=MeshInstance3D.new();var stem:=CylinderMesh.new()
		stem.top_radius=.035;stem.bottom_radius=.055;stem.height=at.y
		stem.radial_segments=8;stem.material=metal;stand.mesh=stem
		stand.position=Vector3(at.x,at.y*.5,at.z);add_child(stand)
		# Floor-standing can and stem are solid; the player walks around them.
		var body:=StaticBody3D.new();stand.add_child(body)
		var shape:=CollisionShape3D.new();var bounds:=BoxShape3D.new()
		bounds.size=Vector3(.55,at.y+.3,.55);shape.shape=bounds;shape.position.y=.15
		body.add_child(shape)

func glowing(color: Color, strength: float) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=color*.28
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=minf(.65,strength*.4)
	return mat

func bulb(at: Vector3, color: Color, radius: float) -> void:
	var node:=MeshInstance3D.new();var sphere:=SphereMesh.new()
	sphere.radius=radius;sphere.height=radius*2;sphere.radial_segments=8;sphere.rings=4
	sphere.material=glowing(color,1.4);node.mesh=sphere;node.position=at
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
	# Small local halos work in Compatibility, where full-screen bloom is absent.
	var gradient:=Gradient.new()
	gradient.colors=PackedColorArray([Color(color.r,color.g,color.b,.13),Color(color.r,color.g,color.b,0)])
	var glow:=GradientTexture2D.new();glow.width=64;glow.height=64;glow.gradient=gradient
	glow.fill=GradientTexture2D.FILL_RADIAL;glow.fill_from=Vector2(.5,.5);glow.fill_to=Vector2(1,.5)
	var haze:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2.ONE*radius*8
	var material:=StandardMaterial3D.new();material.albedo_texture=glow
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	quad.material=material;haze.mesh=quad;haze.position=at
	haze.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(haze)

func pendant(at: Vector3, color: Color) -> Array[Node3D]:
	var before:=get_child_count()
	bulb(at,color,.085)
	var shade:=MeshInstance3D.new();var cone:=CylinderMesh.new()
	cone.top_radius=.12;cone.bottom_radius=.34;cone.height=.20;cone.radial_segments=12
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("252923");mat.metallic=.45;mat.roughness=.8
	cone.material=mat;shade.mesh=cone;shade.position=at+Vector3(0,.13,0);add_child(shade)
	var nodes:Array[Node3D]=[]
	for child in get_children().slice(before):nodes.append(child)
	return nodes

func hang(top: Vector3, fitting: Array[Node3D]) -> void:
	# Run the cable to whatever actually sits above: canvas, deck or beam.
	await get_tree().physics_frame
	if not is_instance_valid(game):return
	var query:=PhysicsRayQueryParameters3D.create(top,top+Vector3(0,40,0),1,[game.player.get_rid()])
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		for node in fitting:node.hide()
		return
	wire(top,hit.position)

func wire(a: Vector3,b: Vector3) -> void:
	var node:=MeshInstance3D.new();var mesh:=CylinderMesh.new()
	mesh.top_radius=.008;mesh.bottom_radius=.008;mesh.height=a.distance_to(b);mesh.radial_segments=4
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("202329");mat.roughness=1
	mesh.material=mat;node.mesh=mesh;node.position=(a+b)*.5;add_child(node)

func add_dust(at: Vector3, extent: Vector3) -> void:
	var dust:=CPUParticles3D.new();dust.name="LightDust"
	dust.position=at;dust.amount=36;dust.lifetime=18;dust.preprocess=18
	dust.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX;dust.emission_box_extents=extent
	dust.direction=Vector3(.2,1,.1);dust.spread=100;dust.gravity=Vector3.ZERO
	dust.initial_velocity_min=.025;dust.initial_velocity_max=.065
	dust.scale_amount_min=.006;dust.scale_amount_max=.014
	var mesh:=SphereMesh.new();mesh.radius=.5;mesh.height=1;mesh.radial_segments=4;mesh.rings=2
	var mat:=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color=Color(.75,.65,.48,.22);mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material=mat;dust.mesh=mesh;dust.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)

func sync() -> void:
	for light in fixed_spots:
		if light.name=="ClinicTask":light.visible=game.phase in ["technical","photos","walter","contract","roof_key","trapped","captured"]
	var late:bool=game.phase in ["return_arena","roof_access","roof","home","bathroom","captured","trapped"] or (game.phase=="complete" and game.flags.get("ending_id","")=="captured")
	var mode:=2 if late else (1 if game.phase=="intro" else 0)
	if mode==show_mode:return
	var first:=show_mode<0;show_mode=mode
	if show_fade:show_fade.kill()
	show_fade=create_tween().set_parallel(true)
	for light in fixed_spots:
		var energy:float=light.get_meta("show_energy")
		if mode==2 and light.name!="DressingKey":energy=3.0 if light.name=="StageKey" else 0.0
		elif light in show_spots:energy*=1.0 if mode==1 else (.0 if mode==2 else .78)
		if first:light.light_energy=energy
		else:show_fade.tween_property(light,"light_energy",energy,2.0)
		var beam:ShaderMaterial=light.get_meta("beam_material") if light.has_meta("beam_material") else null
		if beam:
			if first:beam.set_shader_parameter("strength",1.0 if mode==1 else (.0 if mode==2 else .78))
			else:show_fade.tween_property(beam,"shader_parameter/strength",1.0 if mode==1 else (.0 if mode==2 else .78),2.0)
	for index in 3:
		var light:OmniLight3D=lamps[index]
		var energy:float=.025 if mode==2 else float(light.get_meta("rest_energy"))
		if first:light.light_energy=energy
		else:show_fade.tween_property(light,"light_energy",energy,2.0)
	if first:show_fade.kill()

func pause_motion(value: bool) -> void:
	if value:
		fade_paused=show_fade!=null and show_fade.is_valid() and show_fade.is_running()
		if fade_paused:show_fade.pause()
	elif fade_paused:
		if show_fade and show_fade.is_valid():show_fade.play()
		fade_paused=false

func add_shaft(light: SpotLight3D, target: Vector3) -> void:
	# Two narrow cores supply the sense of dusty air, using a bounded 12-sample
	# shader rather than renderer-specific volumetric fog. Other lights stay cheap.
	var direction:Vector3=(target-light.position).normalized()
	var length:float=light.position.distance_to(target)+.5
	var beam:=MeshInstance3D.new();beam.name=String(light.name)+"Haze"
	var mesh:=CylinderMesh.new();mesh.top_radius=.045;mesh.bottom_radius=length*.21;mesh.height=length;mesh.radial_segments=24
	var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/shaders/theatre_haze.gdshader")
	mat.set_shader_parameter("source_position",light.position)
	mat.set_shader_parameter("source_direction",direction)
	mat.set_shader_parameter("beam_color",light.light_color)
	mat.set_shader_parameter("reach",length)
	mesh.material=mat;beam.mesh=mesh;beam.position=light.position+direction*length*.5
	beam.quaternion=Quaternion(Vector3.DOWN,direction)
	beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam);light.set_meta("beam_material",mat)
