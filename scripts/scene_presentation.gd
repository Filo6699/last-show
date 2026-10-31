extends "res://scripts/scene_parts.gd"
## Large, readable scenic groupings added around the authored story props.
## Added curtain panels and canopy posts are physical; imported meshes stay intact.

func setup(owner_game) -> void:
	game=owner_game
	name="ScenePresentation"
	story_trunk_dressing()
	storage_pavilion()
	bruno_backdrop()
	dressing_posters()
	close_dressing_flap()


func story_trunk_dressing() -> void:
	var trunk:=game.model.find_child("StoryTrunk",true,false) as MeshInstance3D
	if trunk==null:return
	# Derive the 16-point octagonal cross-section from the imported barrel mesh.
	# AABB corners turn this rounded prop into a floating square cage, so all new
	# trim follows the actual authored profile instead.
	var arrays:=trunk.mesh.surface_get_arrays(0)
	var mesh_vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var unique:Dictionary={}
	for vertex in mesh_vertices:
		if absf(vertex.y-.35)>.001:continue
		var point:=Vector2(snappedf(vertex.x,.001),snappedf(vertex.z,.001))
		unique[point]=true
	var profile:Array[Vector2]=[]
	for point in unique.keys():profile.append(point)
	profile.sort_custom(func(a:Vector2,b:Vector2)->bool:return atan2(a.y,a.x)<atan2(b.y,b.x))
	if profile.size()<8:return
	for local_y in [-.18,.20]:
		var ring_points:Array[Vector3]=[]
		var center_world:Vector3=trunk.to_global(Vector3(0,local_y,0))
		for point in profile:
			var world_point:=trunk.to_global(Vector3(point.x,local_y,point.y))
			var radial:=Vector2(world_point.x-center_world.x,world_point.z-center_world.z).normalized()
			world_point+=Vector3(radial.x,0,radial.y)*.009
			ring_points.append(world_point)
		for index in ring_points.size():
			var a:Vector3=to_local(ring_points[index])
			var b:Vector3=to_local(ring_points[(index+1)%ring_points.size()])
			rod(a,b,.017,"927247",.42)
	# The nearest front facet is the positive-Z face seen from the main aisle.
	# Its flat section is found from the real profile, not the square AABB.
	var front_z:float=INF
	for point in profile:
		var world_point:=trunk.to_global(Vector3(point.x,0,point.y))
		if world_point.z>0.7:front_z=minf(front_z,world_point.z)
	var face_points:Array[Vector3]=[]
	for point in profile:
		var world_point:=trunk.to_global(Vector3(point.x,0,point.y))
		if absf(world_point.z-front_z)<.002:face_points.append(world_point)
	if face_points.size()<2:return
	var face_x:float=0.0
	for point in face_points:face_x+=point.x
	face_x/=face_points.size()
	var trunk_center_y:float=trunk.to_global(Vector3.ZERO).y
	var plate_at:=Vector3(face_x,trunk_center_y,front_z+.012)
	box(plate_at,Vector3(.16,.20,.025),"a18455",false,.62)
	box(plate_at+Vector3(0,.035,.018),Vector3(.045,.075,.014),"443238",false,.12)
	var handle:=ring(plate_at+Vector3(0,-.075,.029),.047,.011,"c19e61")
	handle.rotation.x=PI/2


func storage_pavilion() -> void:
	# A compact open canopy covers the storage cluster without reading as a
	# separate room inside the main tent.
	var left:=17.6
	var right:=27.8
	var front:=-4.0
	var rear:=-12.8
	var mid:float=(left+right)*.5
	var roof_z:float=(front+rear)*.5
	var roof_length:float=front-rear
	var roof_edge_y:=5.5
	var roof_ridge_y:=6.6
	var slope:float=(roof_ridge_y-roof_edge_y)/((right-left)*.5)
	# Support posts stand outside the prop footprints at the two long edges.
	for x in [left,right]:
		for z in [front+.55,rear-.35]:
			var post:=box(Vector3(x,2.75,z),Vector3(.16,5.5,.16),"3f4744",true,.35)
			post.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			box(Vector3(x,5.35,z),Vector3(.24,.12,.24),"b79b64",false,.5)
	# Two sloping roof planes, striped in wide circus-cloth panels.
	var stripe_count:=8
	var stripe_width:float=(right-left)/stripe_count
	for index in stripe_count:
		var x:float=left+(index+.5)*stripe_width
		var is_left:bool=x<mid
		var signed_slope:float=slope if is_left else -slope
		var height:float=roof_ridge_y-absf(x-mid)*slope
		var panel:=box(Vector3(x,height,roof_z),Vector3(stripe_width+.015,.09,roof_length),"6b3941" if index%2==0 else "978c75")
		panel.rotation.z=signed_slope
	# Gold eaves keep the roof silhouette readable while leaving all four sides open.
	rod(Vector3(left,roof_edge_y,front),Vector3(mid,roof_ridge_y,front),.075,"b39861",.55)
	rod(Vector3(mid,roof_ridge_y,front),Vector3(right,roof_edge_y,front),.075,"b39861",.55)
	rod(Vector3(left,roof_edge_y,rear),Vector3(mid,roof_ridge_y,rear),.075,"b39861",.55)
	rod(Vector3(mid,roof_ridge_y,rear),Vector3(right,roof_edge_y,rear),.075,"b39861",.55)
	# Open eaves reveal the actual stored equipment; no shop-like fascia/sign.


func bruno_backdrop() -> void:
	# A single tall striped curtain gives the training props and Bruno a stage-like
	# context. It stays behind the conversation position and off the approach aisle.
	var wall_x:float=-24.5
	# The gallery's front row begins at r=34.3. End the curtain before that
	# radius so no bench or tread passes through it, and extend it south instead.
	# Starts .4 m clear of the red wagon parked at z 3.6..10.4.
	var wall_start:float=11.0
	var wall_end:float=23.0
	var depth:float=wall_end-wall_start
	var height:float=6.4
	var stripe_count:=12
	var stripe_width:float=depth/stripe_count
	for index in stripe_count:
		var z:float=wall_start+(index+.5)*stripe_width
		var panel:=box(Vector3(wall_x,height*.5,z),Vector3(.12,height,stripe_width+.012),"73333e" if index%2==0 else "a49b85",true)
		panel.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The wall runs along the west edge, clear of the diagonal approach path.
	for z in [wall_start-.12,wall_end+.12]:
		box(Vector3(wall_x,height*.5,z),Vector3(.2,height+.3,.16),"b1965e",false,.48)
	box(Vector3(wall_x,height+.04,(wall_start+wall_end)*.5),Vector3(.2,.20,depth+.4),"393f3b",false,.4)
	box(Vector3(wall_x,height-.72,(wall_start+wall_end)*.5),Vector3(.24,.045,depth-.34),"b1965e",false,.48)
	# A restrained banner over the backdrop completes the silhouette without
	# adding anything at body height near Bruno or the training equipment.
	rod(Vector3(wall_x+.12,7.0,wall_start+.25),Vector3(wall_x+.12,7.0,wall_end-.25),.035,"b1965e",.42)
	for index in int((depth-1.0)/1.7)+1:
		var z:float=wall_start+.5+index*1.7
		var top:=Vector3(wall_x+.12,7.0,z)
		var tip:=top+Vector3(0,-.72,0)
		var mesh:=ArrayMesh.new();var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([top+Vector3(0,0,-.58),top+Vector3(0,0,.58),tip])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var pennant:=mesh_node(mesh,Vector3.ZERO,material("a3865c" if index%2==0 else "4c5650"),"TrainingPennant")
		pennant.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED


func dressing_posters() -> void:
	# These two small boards sit on measured, free plaster panels of the imported
	# dressing-tent wall. Their faces follow the wall and point back into the room.
	framed_affiche(Vector3(-40.08,2.25,34.15),Vector3(-.804,0,.596),"ВОЗДУШНЫЙ\nНОМЕР")
	framed_affiche(Vector3(-41.42,2.25,32.70),Vector3(-.671,0,.741),"СИЛОВОЙ\nНОМЕР")


func close_dressing_flap() -> void:
	# The supplied doorways have a flat black fill and lead nowhere. Shade them
	# as closed canvas flaps instead of unlit holes.
	var flap:=game.model.find_child("Make-up Tent_002",true,false) as MeshInstance3D
	if flap==null:return
	var canvas:=StandardMaterial3D.new();canvas.resource_name="Closed flap canvas"
	canvas.albedo_color=Color("4a1d29");canvas.roughness=1.0
	canvas.cull_mode=BaseMaterial3D.CULL_DISABLED
	flap.material_override=canvas
	# The main tent's east entrance has the same flat black fill. Close it too.
	var entrance:=game.model.find_child("Шатер - главный_003",true,false) as MeshInstance3D
	if entrance:entrance.material_override=canvas


func framed_affiche(surface_point:Vector3,inward_normal:Vector3,title:String) -> void:
	var normal:=Vector3(inward_normal.x,0,inward_normal.z).normalized()
	var yaw:float=atan2(normal.x,normal.z)
	var basis:=Basis(Vector3.UP,yaw)
	var center:=surface_point+normal*.035
	var width:=.54
	var height:=.78
	var frame:=box(center,Vector3(width,height,.055),"49313a")
	frame.rotation.y=yaw
	var paper:=box(center+normal*.034,Vector3(width-.075,height-.075,.014),"c9b995")
	paper.rotation.y=yaw
	for side in [-1,1]:
		var vertical:=box(center+basis*Vector3(side*(width*.5-.025),0,.048),Vector3(.035,height-.025,.025),"ab8c58",false,.35)
		vertical.rotation.y=yaw
		var horizontal:=box(center+basis*Vector3(0,side*(height*.5-.025),.048),Vector3(width-.025,.035,.025),"ab8c58",false,.35)
		horizontal.rotation.y=yaw
	sign_text(title,center+basis*Vector3(0,.22,.06),width*.78,yaw,"50353a")
	# A small circus hoop is the single graphic beneath the heading.
	var emblem:=ring(center+basis*Vector3(0,-.14,.065),.085,.012,"9c794b")
	emblem.rotation.y=yaw
