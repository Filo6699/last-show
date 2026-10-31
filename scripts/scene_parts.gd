extends Node3D
## Reusable, physical set construction. Existing imported art is never moved.
var game
var materials:Dictionary={}
var built_meshes:=0

func material(color:String, metal:=0.0, rough:=-1.0, glow:=0.0, kind:="paint") -> StandardMaterial3D:
	var key:=color+str(metal)+str(rough)+str(glow)+String(kind)
	if materials.has(key):return materials[key]
	var finish_kind:=StringName(kind)
	if finish_kind==&"paint" and metal>.2:finish_kind=&"metal"
	var mat:StandardMaterial3D=preload("res://scripts/set_finish_materials.gd").make_surface(Color(color),finish_kind,metal,rough,glow)
	materials[key]=mat;return mat

func mesh_node(mesh:Mesh, at:Vector3, mat:Material, label:="SetDetail") -> MeshInstance3D:
	var obj:=MeshInstance3D.new();obj.name=label;obj.mesh=mesh
	obj.material_override=mat;obj.position=at
	# Paper, signs, rugs and glass receive shadows without self-shadow striping.
	if mesh is QuadMesh or (mesh is BoxMesh and minf(mesh.size.x,minf(mesh.size.y,mesh.size.z))<.08):
		obj.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(obj);built_meshes+=1
	return obj

func solid(obj:MeshInstance3D, size:Vector3, offset:=Vector3.ZERO) -> StaticBody3D:
	var body:=StaticBody3D.new();obj.add_child(body)
	var shape:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=size
	shape.shape=bounds;shape.position=offset;body.add_child(shape);return body

## Invisible box collider for decorative groups built from many visual parts.
## Several boxes may share one body (pass it back in) to keep body counts low.
## Coordinates are local to this node; a shared body must be one of its blockers.
func blocker(at:Vector3, size:Vector3, yaw:=0.0, body:StaticBody3D=null) -> StaticBody3D:
	if body==null:
		body=StaticBody3D.new();body.name="SetBlocker";add_child(body)
	var shape:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=size
	shape.shape=bounds;shape.position=at;shape.rotation.y=yaw
	body.add_child(shape);return body

func box(at:Vector3, size:Vector3, color:String, physical:=false, metal:=0.0, label:="SetPanel", kind:="paint") -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var obj:=mesh_node(mesh,at,material(color,metal,-1.0,0.0,kind),label)
	if physical:solid(obj,size)
	return obj

func cylinder(at:Vector3, radius:float, height:float, color:String, metal:=0.0, vertices:=12) -> MeshInstance3D:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius
	mesh.height=height;mesh.radial_segments=vertices
	return mesh_node(mesh,at,material(color,metal))

func rod(a:Vector3,b:Vector3,radius:float,color:String,metal:=0.0) -> MeshInstance3D:
	var obj:=cylinder((a+b)*.5,radius,a.distance_to(b),color,metal,8)
	obj.quaternion=Quaternion(Vector3.UP,(b-a).normalized());return obj

func sphere(at:Vector3,size:Vector3,color:String) -> MeshInstance3D:
	var mesh:=SphereMesh.new();mesh.radius=.5;mesh.height=1
	mesh.radial_segments=12;mesh.rings=6
	var obj:=mesh_node(mesh,at,material(color));obj.scale=size;return obj

func ring(at:Vector3, radius:float, tube:float, color:String) -> MeshInstance3D:
	var mesh:=TorusMesh.new();mesh.inner_radius=radius-tube;mesh.outer_radius=radius+tube
	mesh.rings=48;mesh.ring_segments=8
	return mesh_node(mesh,at,material(color))

func sign_text(text:String,at:Vector3,width:=1.0,yaw:=0.0,color:="cfbd9e") -> Label3D:
	var node:=Label3D.new();node.text=text;node.position=at;node.rotation.y=yaw
	node.font=preload("res://assets/fonts/DejaVuSerif.ttf")
	node.font_size=64
	var measured:=1.0
	for line in text.split("\n"):measured=maxf(measured,node.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,64).x)
	node.pixel_size=width/measured;node.outline_size=2
	node.modulate=Color(color);node.shaded=true;node.no_depth_test=false
	add_child(node);return node

func plaque(text:String,at:Vector3,width:=1.5,height:=.65,yaw:=0.0) -> void:
	var panel:=box(at,Vector3(width,height,.055),"28332f")
	panel.rotation.y=yaw
	var normal:=Basis(Vector3.UP,yaw)*Vector3(0,0,.035)
	var letters:=sign_text(text,at+normal,width*.84,yaw)
	var text_height:float=letters.font.get_height(64)*text.split("\n").size()*letters.pixel_size
	if text_height>height*.78:letters.pixel_size*=height*.78/text_height
	# Gold rule and burgundy inset make signs readable against the tent canvas.
	panel.material_override=material("512e38")
	for side in [-1,1]:
		var trim:=box(at+Basis(Vector3.UP,yaw)*Vector3(0,side*(height*.5-.045),.033),Vector3(width-.08,.035,.018),"b49863")
		trim.rotation.y=yaw

func table(at:Vector3,width:=1.7,depth:=.75,color:="5b4633") -> void:
	box(at+Vector3(0,.86,0),Vector3(width,.09,depth),color,true,0.0,"SetPanel","wood")
	for x in [-1,1]:
		for z in [-1,1]:
			box(at+Vector3(x*(width*.5-.10),.41,z*(depth*.5-.10)),Vector3(.075,.82,.075),"3b332c",false,0.0,"SetPanel","wood")
	box(at+Vector3(0,.67,0),Vector3(width-.12,.14,depth-.08),"3e352b",false,0.0,"SetPanel","wood")

func crate(at:Vector3,size:=Vector3(.85,.7,.7),yaw:=0.0) -> void:
	var root:=Node3D.new();root.position=at;add_child(root)
	var start:=get_child_count()
	box(at+Vector3(0,size.y*.5,0),size,"69513a",true,0.0,"SetPanel","wood")
	for side in [-1,1]:
		for level in [.15,.85]:
			box(at+Vector3(0,size.y*level,side*(size.z*.5+.012)),Vector3(size.x+.035,.10,.035),"887051",false,0.0,"SetPanel","wood")
		for x in [-1,1]:box(at+Vector3(x*(size.x*.5-.07),size.y*.5,side*(size.z*.5+.025)),Vector3(.08,size.y,.045),"3d3832",false,.35)
	for node in get_children().slice(start):
		node.reparent(root,true)
	# root positions are already world-aligned above; rotate the completed crate.
	root.rotation.y=yaw

func asset(id:String,at:Vector3,yaw:=0.0,scale_factor:=1.0,physical:=true) -> Node3D:
	var obj:Node3D=load("res://assets/environments/circus_props/stylized/"+id+".glb").instantiate()
	obj.name=id.capitalize()+"Set";add_child(obj);obj.position=at
	obj.rotation.y=yaw;obj.scale=Vector3.ONE*scale_factor
	if physical:
		var bounds:=AABB();var found:=false
		for visual in obj.find_children("*","MeshInstance3D",true,false):
			var relative:Transform3D=obj.global_transform.affine_inverse()*visual.global_transform
			var rect:AABB=relative*visual.get_aabb()
			bounds=bounds.merge(rect) if found else rect;found=true
		if found:
			var body:=StaticBody3D.new();obj.add_child(body)
			var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=bounds.size
			shape.shape=box;shape.position=bounds.get_center();body.add_child(shape)
	return obj

func target(id:String,at:Vector3,size:Vector3,prompt:String,physical:=false) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name=id.capitalize()
	body.set_script(preload("res://scripts/interactable.gd"))
	body.interaction_id=StringName(id);body.prompt=prompt
	body.collision_layer=1 if physical else 16
	add_child(body);body.position=at
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size
	shape.shape=box;body.add_child(shape)
	body.interacted.connect(game.on_interact)
	if not game.targets.has(id):game.targets[id]=[]
	game.targets[id].append(body);return body

func point_light(at:Vector3,color:String,energy:float,reach:float) -> OmniLight3D:
	var light:=OmniLight3D.new();light.position=at;light.light_color=Color(color)
	light.light_energy=energy;light.omni_range=reach;light.shadow_enabled=false
	add_child(light);return light

func batch() -> void:
	var merged:=Node3D.new();merged.name="SetBatches";add_child(merged)
	set_meta("statistics",preload("res://scripts/static_batches.gd").apply(self,merged))
