extends Node3D
## A real stage and small instanced audience; no extra cameras or shadow maps.
var game
var audience: Array[MultiMeshInstance3D] = []
var hand_instances: MultiMeshInstance3D
var seats: Array[Vector3]=[]
var seat_bases: Array[Basis] = []
var applause := 0.0
var cane: MeshInstance3D
var loose_canvas: MeshInstance3D
var animations: Array[Tween]=[]
var debris_nodes: Array[MeshInstance3D]=[]
var view_tween: Tween
var view_active := false
var neutral_pitch := 0.0
var neutral_yaw := 0.0
## This is the breach already cut through the delivered canopy and maintenance
## walk. Keep the opening animation and falling pieces registered to this bay.
const ROOF_BREACH_CENTER := Vector3(-8, 50, -6)
const ROOF_BREACH_X_RANGE := Vector2(-11, -5)
const ROOF_BREACH_Z_RANGE := Vector2(-9, -3)
# Bias the short look slightly toward the unobstructed side of the same cut.
const ROOF_LOOK_TARGET := Vector3(-7.2, 50, -6)
var gallery_count:=0
var ring_mesh:MeshInstance3D
func material(color: String) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=Color(color);m.roughness=.95;return m
func box(at: Vector3, size: Vector3, color: String, collision := false) -> MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.material_override=material(color);node.position=at;add_child(node)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new(); bounds.size = size
		shape.shape = bounds
		node.add_child(body); body.add_child(shape)
	return node
func instances(mesh: Mesh, positions: Array[Vector3], color: String) -> MultiMeshInstance3D:
	var node:=MultiMeshInstance3D.new();var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh;multi.instance_count=positions.size()
	for i in positions.size(): multi.set_instance_transform(i,Transform3D(Basis.IDENTITY,positions[i]))
	node.multimesh=multi;node.material_override=material(color);add_child(node);audience.append(node);return node
func setup(owner_game):
	game=owner_game
	set_process(false)
	# Shallow physical steps connect the opening platform to the walkable ring.
	box(Vector3(0,.07,-4.92),Vector3(3,.14,.55),"5f4030",true)
	box(Vector3(0,.16,-5.22),Vector3(3,.18,.4),"6d4933",true)
	var ring:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=14.5;disc.bottom_radius=14.5;disc.height=.015;disc.radial_segments=96;ring.mesh=disc;ring.position=Vector3(0,.065,.1);ring.material_override=material("633744");ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(ring);ring_mesh=ring
	for x in [-3.8,3.8]:
		box(Vector3(x,2.05,-7.48),Vector3(.35,4.1,.4),"302238")
		for j in 5: box(Vector3(x+(.15*j if x<0 else -.15*j),3.82-j*.06,-7.35),Vector3(.20,.8,.20),"682c36")
	box(Vector3(0,4.25,-7.4),Vector3(8.1,.45,.35),"50212e")
	build_gallery.call_deferred()
	# Fixed theatrical keys are provided by Location/CircusLighting.

	loose_canvas=MeshInstance3D.new()
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(-3.5,0,0),Vector3(-1.8,0,3.1)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.DOWN,Vector3.DOWN,Vector3.DOWN])
	var flap:=ArrayMesh.new();flap.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	loose_canvas.mesh=flap;loose_canvas.material_override=material("682c36");loose_canvas.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	loose_canvas.position=ROOF_BREACH_CENTER+Vector3(1.5,-1.0,-1.5);add_child(loose_canvas);loose_canvas.hide()
	preload("res://scripts/canopy_damage_finish.gd").new().setup(game,self)
	cane=MeshInstance3D.new();var shaft:=CylinderMesh.new();shaft.top_radius=.012;shaft.bottom_radius=.012;shaft.height=.8;shaft.radial_segments=8;cane.mesh=shaft;cane.material_override=material("997f4e");game.player.camera.add_child(cane);cane.position=Vector3(.32,-.55,-.52);cane.hide()
func _process(delta):
	if game.hud.menu.visible or applause<=0: return
	applause-=delta
	if applause <= 0:
		set_process(false)
		return
	var phase := Time.get_ticks_msec() * .006
	for i in seats.size():
		var separation := .055+absf(sin(phase+i*.71))*.15
		for side in 2:
			var p: Vector3=seats[i]+seat_bases[i]*Vector3((-1 if side==0 else 1)*separation,.27,.30)
			hand_instances.multimesh.set_instance_transform(i*2+side,Transform3D(seat_bases[i],p))
func opening_action(action: String):
	var tween:=create_tween();animations.append(tween)
	if action=="cane":
		cane.show();tween.tween_property(cane,"position:y",-.12,.45);tween.tween_interval(.7);tween.tween_property(cane,"position:y",-.55,.45);tween.tween_callback(cane.hide)
	elif action=="bow":
		tween.kill()
		camera_gesture(-.55,.3)
	else:
		game.hud.fade.modulate.a=0;game.hud.fade.show();tween.tween_property(game.hud.fade,"modulate:a",.85,.08);tween.tween_property(game.hud.fade,"modulate:a",0,.15);tween.tween_callback(game.hud.fade.hide)
func start_applause() -> void:
	applause=9.1
	set_process(true)

func roof_crack():
	game.flags["roof_damaged"]=true
	# Leave a clear margin before the 2.2s scene auto-advance.
	camera_aim_at(ROOF_LOOK_TARGET,.9)
	var tween:=create_tween();animations.append(tween)
	loose_canvas.show()
	tween.tween_property(loose_canvas,"rotation:x",1.05,.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for i in 4:
		var start:=Vector3(ROOF_BREACH_CENTER.x-.48+i*.32,ROOF_BREACH_CENTER.y-.15,ROOF_BREACH_CENTER.z-.32+(i%2)*.64)
		var debris:=box(start,Vector3(.12,.18,.11),"615044")
		debris_nodes.append(debris)
		var fall:=create_tween().set_parallel(true);animations.append(fall)
		fall.tween_property(debris,"position:y",.09,1.5+i*.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.tween_property(debris,"rotation",Vector3(i+2,1,i),1.2)
		fall.chain().tween_interval(3);fall.tween_callback(debris.queue_free)
func camera_gesture(offset: float, hold: float) -> void:
	if view_tween and view_tween.is_valid(): view_tween.kill()
	if view_active: game.player.camera.rotation.x=neutral_pitch
	if view_active: game.player.rotation.y=neutral_yaw
	neutral_pitch=game.player.camera.rotation.x
	neutral_yaw=game.player.rotation.y
	view_active=true
	view_tween=create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	view_tween.tween_property(game.player.camera,"rotation:x",neutral_pitch+offset,.5)
	view_tween.tween_interval(hold)
	view_tween.tween_property(game.player.camera,"rotation:x",neutral_pitch,.7)
	view_tween.tween_callback(func(): view_active=false)

func camera_aim_at(target: Vector3, hold: float) -> void:
	if view_tween and view_tween.is_valid(): view_tween.kill()
	if view_active:
		game.player.camera.rotation.x=neutral_pitch
		game.player.rotation.y=neutral_yaw
	neutral_pitch=game.player.camera.rotation.x
	neutral_yaw=game.player.rotation.y
	view_active=true
	var direction:Vector3=(target-game.player.camera.global_position).normalized()
	var target_yaw:=atan2(-direction.x,-direction.z)
	var target_pitch:=atan2(direction.y,Vector2(direction.x,direction.z).length())
	view_tween=create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var look_at_breach:=func(amount:float):
		game.player.rotation.y=lerp_angle(neutral_yaw,target_yaw,amount)
		game.player.camera.rotation.x=lerpf(neutral_pitch,target_pitch,amount)
	view_tween.tween_method(look_at_breach,0.0,1.0,.4)
	view_tween.tween_interval(hold)
	var return_to_neutral:=func(amount:float):
		game.player.rotation.y=lerp_angle(target_yaw,neutral_yaw,amount)
		game.player.camera.rotation.x=lerpf(target_pitch,neutral_pitch,amount)
	view_tween.tween_method(return_to_neutral,0.0,1.0,.45)
	view_tween.tween_callback(func(): view_active=false)

func pause_motion(value: bool) -> void:
	for tween in animations + ([view_tween] if view_tween else []):
		if tween and tween.is_valid():
			if value: tween.pause()
			else: tween.play()

func sync_damage() -> void:
	var seating := get_node_or_null("FinishedGallery")
	if is_instance_valid(seating): seating.sync_lighting()
	for node in audience: node.visible=game.phase=="intro" or game.flags.get("roof_audience",false)
	if game.flags.get("roof_damaged",false) or game.phase!="intro":
		loose_canvas.show();loose_canvas.rotation.x=1.05

func build_gallery() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(game):return
	var gallery := preload("res://scripts/gallery.gd").new()
	add_child(gallery); gallery.setup(game, self)
	seats = gallery.occupied; seat_bases = gallery.seat_bases
	hand_instances = gallery.hands; gallery_count = seats.size()
	sync_damage()

func reset():
	if view_tween and view_tween.is_valid(): view_tween.kill()
	if view_active:
		game.player.camera.rotation.x=neutral_pitch
		game.player.rotation.y=neutral_yaw
	view_active=false
	for debris in debris_nodes:
		if is_instance_valid(debris): debris.queue_free()
	debris_nodes.clear()
	for tween in animations:
		if tween and tween.is_valid(): tween.kill()
	animations.clear();applause=0
	set_process(false)
	if is_instance_valid(cane): cane.hide()
	if is_instance_valid(loose_canvas):loose_canvas.hide();loose_canvas.rotation=Vector3.ZERO

func finish_opening() -> void:
	if view_tween and view_tween.is_valid(): view_tween.kill()
	if view_active:
		game.player.camera.rotation.x=neutral_pitch
		game.player.rotation.y=neutral_yaw
	view_active=false
	cane.hide()
	game.hud.fade.hide()
