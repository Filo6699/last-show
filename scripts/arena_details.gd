extends "res://scripts/scene_parts.gd"
## Three performance stations occupy the apron between ring and gallery.
## Everything here is new scenery; the delivered scene stays in place.
var ball:MeshInstance3D
var plates:Array[Node3D]=[]
var motions:Dictionary={}
var paused_motions:Array[Tween]=[]
const IDS:=["balance_chairs","spinning_plates","balance_ball","acrobat_wheel"]

func setup(owner_game) -> void:
	game=owner_game;name="ArenaDetails"
	chair_station()
	plate_station()
	ball_station()
	acrobat_station()
	ring_paint()
	# Thin rails/strings remain lit, but do not spend shadow-map draws on
	# subpixel silhouettes. Seats, drums, the globe and wheel retain their shadows.
	for visual in find_children("*","MeshInstance3D",true,false):
		if visual.mesh is CylinderMesh and visual.mesh.top_radius<=.07:
			visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Each station is under eight metres wide. Merge its fixed rails/legs by
	# material before the venue-wide pass; outlines and moving parts stay separate.
	for label in ["ChairBalance","PlateBalance","RollingGlobe","AcrobatWheel"]:
		var station_root:Node3D=get_node(label)
		var merged:=Node3D.new();merged.name="StationBatches";station_root.add_child(merged)
		merged.set_meta("statistics",preload("res://scripts/static_batches.gd").apply(station_root,merged,0.0))

func station(label:String,at:Vector3) -> Node3D:
	var parts:=preload("res://scripts/scene_parts.gd").new()
	parts.game=game;parts.materials=materials;parts.name=label;add_child(parts)
	parts.position=at;parts.rotation.y=atan2(-at.x,-at.z)
	return parts

func rug(parts:Node3D,size:Vector2,color:String) -> void:
	# One shared, worn practice canvas ties the separate apparatus together.
	# The former bright gold frames made every station read as a tiny kiosk.
	parts.box(Vector3(0,.022,0),Vector3(size.x,.012,size.y*.98),"3d403b")

func obstruction(parts:Node3D,at:Vector3,size:Vector3) -> void:
	var body:=StaticBody3D.new();parts.add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size
	collision.shape=shape;collision.position=at;body.add_child(collision)

func chair(parts:Node3D,at:Vector3,yaw:float) -> MeshInstance3D:
	var assembly:=preload("res://scripts/scene_parts.gd").new()
	assembly.materials=parts.materials
	parts.add_child(assembly);assembly.position=at;assembly.rotation.y=yaw
	var seat:MeshInstance3D=assembly.box(Vector3(0,.78,0),Vector3(.90,.12,.84),"713c43")
	assembly.box(Vector3(0,.855,0),Vector3(.72,.06,.66),"b1905c")
	for side in [-1,1]:
		for z in [-.31,.31]:
			assembly.rod(Vector3(side*.34,0,z),Vector3(side*.34,.8,z),.045,"66533c")
		assembly.rod(Vector3(side*.34,.8,-.31),Vector3(side*.34,1.72,-.31),.045,"9c8151")
		assembly.rod(Vector3(side*.34,.30,-.31),Vector3(side*.34,.30,.31),.025,"9c8151")
	assembly.box(Vector3(0,1.47,-.31),Vector3(.72,.38,.075),"713c43")
	assembly.rod(Vector3(-.34,1.72,-.31),Vector3(.34,1.72,-.31),.035,"b69b66")
	return seat

func chair_station() -> void:
	var parts:=station("ChairBalance",Vector3(-18,0,2))
	rug(parts,Vector2(4.8,4.4),"344340")
	# A genuinely connected stack: each next chair stands on the preceding seat.
	for index in 4:
		chair(parts,Vector3(-.65+index*.10,.06+index*.86,-.3),.12 if index%2==1 else -.06)
	obstruction(parts,Vector3(-.50,2.27,-.3),Vector3(1.40,4.45,1.12))
	var seat:=chair(parts,Vector3(1.0,.06,.5),-.45)
	seat.set_meta("dynamic_set",true)
	obstruction(parts,Vector3(1,.65,.5),Vector3(1.0,1.25,1.1))
	# Folded crash mat and a chalked handprint keep this a working practice spot.
	parts.box(Vector3(-.9,.23,-1.65),Vector3(2.2,.42,.75),"6c4047",true)
	for x in [-1.55,-.95,-.35]:parts.box(Vector3(x,.45,-1.65),Vector3(.03,.02,.66),"a89677")
	var inspect:StaticBody3D=parts.target("balance_chairs",Vector3(1,.90,1.10),Vector3(.85,.35,.35),"Осмотреть балансировочные стулья")
	inspect.set_meta("outline_meshes",[seat])
	lamp(parts,Vector3(1.85,3.0,-1.4),"e9c492",.8)

func plate_station() -> void:
	var parts:=station("PlateBalance",Vector3(17,0,7))
	rug(parts,Vector2(4.4,4.8),"51343b")
	# A freestanding A-frame ladder, six real rungs and spread feet.
	for side in [-1,1]:
		for foot in [-1,1]:
			parts.rod(Vector3(side*.58,.05,foot*.92-.7),Vector3(side*.58,4.7,-.7),.065,"773843")
		parts.rod(Vector3(side*.58,1.45,-1.35),Vector3(side*.58,1.45,-.05),.035,"675c48")
	for index in 7:
		var h:float=.45+index*.56
		parts.rod(Vector3(-.58,h,.22-h*.196),Vector3(.58,h,.22-h*.196),.055,"b39867")
	obstruction(parts,Vector3(0,2.4,-.7),Vector3(1.25,4.8,1.9))
	parts.box(Vector3(0,.77,1.0),Vector3(3.3,.12,.55),"514437",true)
	for x in [-1,1]:
		for z in [-1,1]:
			parts.rod(Vector3(x*1.43,.08,1.0+z*.20),Vector3(x*1.31,.72,1.0+z*.15),.065,"594635")
	for index in 3:
		var x:float=(index-1)*1.05
		var height:float=2.8+index*.55
		parts.rod(Vector3(x,.7,1.0),Vector3(x,height,1.0),.026,"b49c65")
		var pivot:=Node3D.new();parts.add_child(pivot);pivot.position=Vector3(x,height,1.0)
		pivot.set_meta("dynamic_set",true);plates.append(pivot)
		var disc:MeshInstance3D=parts.cylinder(Vector3.ZERO,.44,.055,"c2b18b",0,24)
		disc.reparent(pivot,false)
		var underside:MeshInstance3D=parts.cylinder(Vector3(0,-.033,0),.42,.015,"3f5955",0,24)
		underside.reparent(pivot,false)
		var rim:MeshInstance3D=parts.ring(Vector3(0,.031,0),.41,.019,"a57d48")
		rim.reparent(pivot,false)
		var stripe:MeshInstance3D=parts.box(Vector3(.12,.031,0),Vector3(.035,.008,.64),"763d45")
		stripe.reparent(pivot,false)
		var lower_stripe:MeshInstance3D=parts.box(Vector3(.12,-.046,0),Vector3(.035,.008,.62),"b9a16b")
		lower_stripe.reparent(pivot,false)
	var crank:MeshInstance3D=parts.rod(Vector3(1.45,1.0,1.15),Vector3(1.45,1.0,1.62),.07,"b89a61")
	crank.set_meta("dynamic_set",true)
	var inspect:StaticBody3D=parts.target("spinning_plates",Vector3(1.45,1.0,1.65),Vector3(.32,.32,.26),"Раскрутить тарелки")
	inspect.set_meta("outline_meshes",[crank])
	lamp(parts,Vector3(-1.8,3.2,-1.65),"c4d0c4",.65)

func ball_station() -> void:
	var parts:=station("RollingGlobe",Vector3(18,0,1))
	rug(parts,Vector2(4.5,4.5),"464b3c")
	parts.box(Vector3(0,.20,.1),Vector3(2.5,.36,2.5),"534535",true)
	for side in [-1,1]:
		parts.box(Vector3(side*1.05,.5,.1),Vector3(.14,.55,2.35),"987b4f",true)
	ball=parts.sphere(Vector3(0,1.45,.1),Vector3.ONE*2.15,"a18e68")
	ball.name="BalanceGlobe";ball.set_meta("dynamic_set",true)
	var paint:=ShaderMaterial.new();paint.shader=preload("res://assets/shaders/circus_ball.gdshader")
	ball.material_override=paint
	var body:=StaticBody3D.new();ball.add_child(body)
	var shape:=CollisionShape3D.new();var sphere_shape:=SphereShape3D.new();sphere_shape.radius=.5
	shape.shape=sphere_shape;body.add_child(shape)
	# A pair of open wooden braces steadies the globe. A full-height folding screen
	# used to enclose it like a booth and hid the tent behind the apparatus.
	for side in [-1,1]:
		parts.rod(Vector3(side*1.34,.1,.55),Vector3(side*1.34,1.65,-.72),.055,"594635")
		parts.rod(Vector3(side*1.34,1.65,-.72),Vector3(side*1.34,.1,-1.5),.055,"594635")
		parts.rod(Vector3(side*1.34,.56,-1.13),Vector3(side*1.34,.56,.12),.04,"8a724f")
	var inspect:StaticBody3D=parts.target("balance_ball",Vector3(0,1.45,1.22),Vector3(1.2,.8,.20),"Толкнуть балансировочный шар")
	inspect.set_meta("outline_meshes",[ball])
	lamp(parts,Vector3(1.9,3.0,-1.6),"e2bc88",.65)

func lamp(parts:Node3D,at:Vector3,color:String,energy:float) -> void:
	parts.rod(Vector3(at.x,.05,at.z),at+Vector3(0,.3,0),.025,"4b5149")
	var shade:MeshInstance3D=parts.cylinder(at+Vector3(0,.12,0),.22,.14,"393f3b")
	shade.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb:MeshInstance3D=parts.sphere(at,Vector3.ONE*.12,color)
	bulb.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.material_override=parts.material(color,0,.5,1.0)
	parts.point_light(at-Vector3(0,.12,0),color,energy,7.0)

func acrobat_station() -> void:
	var parts:=station("AcrobatWheel",Vector3(2,0,18))
	rug(parts,Vector2(7.4,4.2),"3f4b48")
	for entry in [[Vector3(-2.55,.36,0),.70],[Vector3(2.55,.56,-.35),1.10]]:
		var at:Vector3=entry[0];var height:float=entry[1]
		var drum:MeshInstance3D=parts.cylinder(at, .82,height,"773e47",0,16)
		var body:=StaticBody3D.new();drum.add_child(body)
		var collision:=CollisionShape3D.new();var shape:=CylinderShape3D.new();shape.radius=.82;shape.height=height
		collision.shape=shape;body.add_child(collision)
		parts.cylinder(at+Vector3(0,height*.5+.025,0),.84,.045,"ac9569",0,16)
		for index in 8:
			var angle:float=TAU*index/8
			var trim:MeshInstance3D=parts.box(at+Vector3(sin(angle)*.8,0,cos(angle)*.8),Vector3(.12,height*.8,.035),"b29b70")
			trim.rotation.y=angle
	var wheel:MeshInstance3D=parts.ring(Vector3(0,1.72,0),1.65,.065,"b39a67")
	wheel.name="CyrWheel";wheel.rotation.x=PI/2
	wheel.set_meta("dynamic_set",true)
	var wheel_body:=StaticBody3D.new();wheel.add_child(wheel_body)
	var wheel_shape:=CollisionShape3D.new();wheel_shape.shape=wheel.mesh.create_trimesh_shape();wheel_body.add_child(wheel_shape)
	for side in [-1,1]:
		parts.box(Vector3(side*.7,.14,.05),Vector3(.65,.24,1.05),"64503a",true)
		parts.rod(Vector3(side*.9,.2,-.4),Vector3(side*1.25,.75,0),.04,"7e7858")
	var inspect:StaticBody3D=parts.target("acrobat_wheel",Vector3(1.45,1.55,.15),Vector3(.40,.8,.25),"Осмотреть акробатический обод")
	inspect.set_meta("outline_meshes",[wheel])
	lamp(parts,Vector3(-3.2,3.1,-1.45),"dfc29b",.65)

func ring_paint() -> void:
	# Faded, short rays suggest a worn ring center without competing with the act.
	# The previous broad, bright wedges looked like a plastic graphic overlay.
	var paint:Material=game.full_game.set_dressing.floor_material(Color("59413f"))
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	for index in 10:
		var angle:float=TAU*index/10
		for pair in [[angle+.045,2.7],[angle,7.4],[angle-.045,2.7]]:
			vertices.append(Vector3(sin(pair[0])*pair[1],.076,cos(pair[0])*pair[1]))
			normals.append(Vector3.UP)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var rays:=mesh_node(mesh,Vector3.ZERO,paint,"RingSunburst")
	rays.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func inner_festoons() -> void:
	# Suspend a human-scale visual frame from the existing added lighting towers.
	# No new posts, walls or collision across any walking route.
	for side in [-1,1]:
		var a:=Vector3(side*13.5,6.2,-10.5)
		var b:=Vector3(side*13.5,6.2,12.5)
		for index in 16:
			var t0:float=index/16.0;var t1:float=(index+1)/16.0
			var p:Vector3=a.lerp(b,t0)-Vector3(0,sin(t0*PI)*.9,0)
			var q:Vector3=a.lerp(b,t1)-Vector3(0,sin(t1*PI)*.9,0)
			rod(p,q,.012,"7b704f")
			var center:Vector3=(p+q)*.5
			var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([center+Vector3(0,0,-.45),center+Vector3(0,0,.45),center+Vector3(0,-.65,0)])
			var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var flag:=mesh_node(mesh,Vector3.ZERO,material(["703943","9b865e","3e5551"][index%3]),"ApronPennant")
			flag.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flag.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED

func interact(id:StringName) -> bool:
	if String(id) not in IDS:return false
	if not available():return true
	match String(id):
		"balance_chairs":
			game.hud.show_notice("Четыре стула один на другом. На сиденьях — следы каблуков и мела.")
			game.audio.play("sfx_creak_wood_02",-15,game.targets[String(id)][0].global_position)
		"spinning_plates":
			var tween:=motion("plates")
			for plate in plates:
				tween.tween_property(plate,"rotation:y",plate.rotation.y+TAU*2,3.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tween.tween_method(wobble.bind(plate),0.0,TAU*4,3.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			game.audio.play("sfx_elsa_rig_creak_02",-19,game.targets[String(id)][0].global_position)
			game.hud.show_notice("Ручка ещё работает. Тарелки медленно раскручиваются.")
		"balance_ball":
			var tween:=motion("ball")
			tween.tween_property(ball,"rotation:z",ball.rotation.z+TAU,2.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			game.audio.play("sfx_creak_wood_04",-16,ball.global_position)
			game.hud.show_notice("Тяжёлый шар поворачивается в деревянной подставке.")
		"acrobat_wheel":
			game.audio.play("sfx_elsa_rig_creak_01",-18,game.targets[String(id)][0].global_position)
			game.hud.show_notice("На внутренней стороне обода стёрта краска — здесь держатся руками и ногами.")
	return true

func motion(id:String) -> Tween:
	if motions.has(id) and motions[id].is_valid():motions[id].kill()
	var tween:=create_tween().set_parallel(true);motions[id]=tween
	return tween

func wobble(angle:float,plate:Node3D) -> void:
	plate.rotation.z=sin(angle)*.12

func available() -> bool:
	return game.phase in ["news","to_dressing","mirror","elsa_dressing","to_hall","lili","bruno","elsa_hall","to_technical"]

func sync() -> void:
	var active:bool=available()
	for id in IDS:
		for item in game.targets.get(id,[]):item.collision_layer=16 if active else 0
	if not active:reset_motion()

func reset_motion() -> void:
	for tween in motions.values():
		if tween.is_valid():tween.kill()
	motions.clear();paused_motions.clear()
	ball.rotation.z=0
	for plate in plates:plate.rotation=Vector3.ZERO

func safe_saved_position(saved:Vector3) -> Vector3:
	# 0.3.2 allowed saving on ground now occupied by a new station. Move only
	# avatars actually inside this new scenery, preserving ordinary saved views.
	var capsule:=CapsuleShape3D.new();capsule.height=1.6;capsule.radius=.3
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule
	query.collision_mask=1;query.exclude=[game.player.get_rid()]
	query.transform.origin=saved+Vector3(0,.9,0)
	var space:=get_world_3d().direct_space_state
	var inside_new:=false
	for hit in space.intersect_shape(query,64):
		if is_ancestor_of(hit.collider):inside_new=true;break
	if not inside_new:return saved
	for step in range(1,11):
		for direction in 16:
			var angle:float=TAU*direction/16.0
			var candidate:=saved+Vector3(sin(angle),0,cos(angle))*step*.5
			if not game.is_inside_location(candidate):continue
			query.transform.origin=candidate+Vector3(0,.9,0)
			if space.intersect_shape(query,1).is_empty():return candidate
	return Vector3(0,.05,3)

func pause_motion(value:bool) -> void:
	if value:
		paused_motions.clear()
		for tween in motions.values():
			if tween.is_valid() and tween.is_running():tween.pause();paused_motions.append(tween)
	else:
		for tween in paused_motions:
			if tween.is_valid():tween.play()
		paused_motions.clear()
