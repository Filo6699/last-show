extends "res://scripts/scene_parts.gd"
## Wooden maintenance catwalks INSIDE the upper canopy, and the home interior.
const ROOF_FLOOR:=39.90
const ROOF_ENTRY:=Vector3(-10,40.02,-18)
const ROOF_RETURN:=Vector3(-10.56,40.6,-19.4)
# Service mast behind the rear curtain. It carries the catwalk end; the ladder
# on its west face rises through a hatch in the deck. The arena barrier wall at
# radius 24 leaves room for the gate only on this side.
const MAST:=Vector3(-10,0,-19.4)
const HATCH_X:=-10.5
const ROPE:=Vector3(-10.1,41.05,-10)
const TRAMPOLINE:=Vector3(5.3,40.85,-2)
# High wire between two pedestal boards, mirrored about the deck centre x=-1.75
# the way a real circus rigs it: twin masts, twin boards, the wire over the ring.
const WIRE_A:=-6.5
const WIRE_B:=2.5
const WIRE_Z:=-2.0
const EAST_MAST_X:=6.5
const AUDIENCE_VIEW:=Vector3(6.5,41.65,-.1)
const AUDIENCE_LOOK:=Vector3(-8,50,-6)
const HOME:=Vector3(155,.05,0)
const HOME_MIRROR:=Vector3(155,1.7,-10.85)
var bathroom_glass:MeshInstance3D
var rope_piece:MeshInstance3D
var medicine_bag:Node3D
var pill_cap:MeshInstance3D
var loose_pills:Array[MeshInstance3D]=[]
var roof_door:StaticBody3D
var ladder_top:Array[MeshInstance3D]=[]
var roof:Node3D
var home:Node3D
var roof_env:Environment
var home_env:Environment

func setup(owner_game) -> void:
	game=owner_game;name="LaterLocations"
	service_mast();make_roof();make_home()
	roof_env=game.get_node("World/WorldEnvironment").environment.duplicate()
	roof_env.background_color=Color("0b0b12");roof_env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	roof_env.ambient_light_color=Color("b9a58d");roof_env.ambient_light_energy=.30
	roof_env.fog_enabled=true;roof_env.fog_mode=Environment.FOG_MODE_DEPTH
	roof_env.fog_depth_begin=40;roof_env.fog_depth_end=100;roof_env.fog_light_color=Color("18141b")
	home_env=roof_env.duplicate();home_env.background_color=Color("9aa6a2")
	home_env.ambient_light_color=Color("d6dacb");home_env.ambient_light_energy=.52;home_env.fog_enabled=false
	batch()
	anchor_catwalk.call_deferred()

func anchor_catwalk() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(game): return
	for x in [-8.0, 6.0]:
		var bottom := Vector3(x, ROOF_FLOOR + 3.1, -2)
		var hit := canopy_above(bottom)
		if not hit.is_empty():
			rod(bottom, hit.position - Vector3(0,.08,0), .035, "5b5445", .55)
	# Suspension cables meet the real canopy, replacing hanging fake legs.
	for z in [-18.0, -12.0, -5.0]:
		for x in [-11.35, -8.65, EAST_MAST_X-1.35, EAST_MAST_X+1.35]:
			var bottom := Vector3(x, ROOF_FLOOR, z)
			var canopy := canopy_above(bottom + Vector3(0, .3, 0))
			if not canopy.is_empty():
				rod(bottom, canopy.position - Vector3(0, .08, 0), .025, "5b5445", .55)
	var hit := canopy_above(ROPE + Vector3(0,3,0))
	if not hit.is_empty():
		var bottom := ROPE - Vector3(0,.5,0)
		var top: Vector3 = hit.position - Vector3(0,.08,0)
		rope_piece.mesh.height = top.distance_to(bottom)
		rope_piece.position = (top + bottom) * .5

func canopy_above(at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at, Vector3(at.x,65,at.z),1,[game.player.get_rid()])
	for step in 12:
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {}
		if String(hit.collider.get_meta("source_mesh","")).contains("Шатер"): return hit
		query.exclude.append(hit.collider.get_rid())
	return {}

func service_mast() -> void:
	var top:=ROOF_FLOOR-.24
	var half:=.5
	# Four-chord steel truss from a floor plate to the underside of the deck.
	box(MAST+Vector3(0,.06,0),Vector3(1.5,.12,1.5),"3a3c38",true,.5)
	for x in [-half,half]:
		for z in [-half,half]:
			rod(MAST+Vector3(x,.12,z),MAST+Vector3(x,top,z),.045,"5d6762",.7)
			box(MAST+Vector3(x,.16,z),Vector3(.16,.08,.16),"2f3431",false,.6)
	var level:=.12
	var flip:=1.0
	while level<top-.5:
		var next:=minf(level+2.0,top)
		for face in 4:
			var a:=Basis(Vector3.UP,face*PI/2)*Vector3(-half,0,half)
			var b:=Basis(Vector3.UP,face*PI/2)*Vector3(half,0,half)
			rod(MAST+a+Vector3(0,next,0),MAST+b+Vector3(0,next,0),.025,"6d766f",.7)
			if flip>0:rod(MAST+a+Vector3(0,level,0),MAST+b+Vector3(0,next,0),.02,"6d766f",.7)
			else:rod(MAST+b+Vector3(0,level,0),MAST+a+Vector3(0,next,0),.02,"6d766f",.7)
		level=next;flip=-flip
	# The truss is solid to the player up to head height.
	box(MAST+Vector3(0,1.5,0),Vector3(1.1,3,1.1),"000000",true).visible=false
	# Fixed ladder on the west face: local x runs along the rungs, local z away
	# from the mast towards the climber's back.
	var face:=Vector3(MAST.x-half-.06,0,MAST.z)
	var across:=Vector3(0,0,1)
	var out:=Vector3(-1,0,0)
	for side in [-.24,.24]:
		var foot:Vector3=face+across*side
		rod(foot,foot+Vector3(0,ROOF_FLOOR+1.1,0),.028,"8a8f84",.75)
		# Grab rails above the hatch are part of the descent target outline.
		var grab:MeshInstance3D=rod(foot+Vector3(0,ROOF_FLOOR+1.1,0),foot+Vector3(0,ROOF_FLOOR+1.1,0)-out*.35,.028,"8a8f84",.75)
		ladder_top.append(grab)
		ladder_top.append(rod(foot+Vector3(0,ROOF_FLOOR,0),foot+Vector3(0,ROOF_FLOOR+1.1,0),.03,"8a8f84",.75))
	var rung:=.3
	while rung<ROOF_FLOOR-.1:
		rod(face+Vector3(0,rung,0)-across*.24,face+Vector3(0,rung,0)+across*.24,.016,"9a9d90",.75)
		rung+=.3
	var bracket:=1.5
	while bracket<top:
		for side in [-.24,.24]:rod(face+across*side+Vector3(0,bracket,0),face+across*side+Vector3(0,bracket,0)-out*.06,.02,"5d6762",.7)
		bracket+=3.0
	var points:Array[Vector3]=[]
	for i in 7:
		var angle:=PI*i/6.0
		points.append(face+across*cos(angle)*.36+out*(.08+sin(angle)*.6))
	var hoop:=2.4
	while hoop<ROOF_FLOOR-.5:
		for i in 6:rod(points[i]+Vector3(0,hoop,0),points[i+1]+Vector3(0,hoop,0),.014,"7b8178",.75)
		hoop+=1.4
	for i in [1,3,5]:
		rod(points[i]+Vector3(0,2.4,0),points[i]+Vector3(0,ROOF_FLOOR-.3,0),.012,"7b8178",.75)
	# Padlocked gate in front of the lowest rungs; the target is the gate itself.
	var gate_at:=face+out*.72
	roof_door=target("roof_door",gate_at+Vector3(0,1.1,0),Vector3(.12,2.2,.86),"Служебная лестница",true)
	roof_door.set_meta("dynamic_set",true)
	var gate:=Node3D.new();gate.name="GateParts";roof_door.add_child(gate)
	var frame:=[[-.4,0,-.4,2.1],[.4,0,.4,2.1],[-.4,2.1,.4,2.1],[-.4,.08,.4,.08],[-.4,1.05,.4,1.05]]
	for part in frame:
		rod(gate_at+across*part[0]+Vector3(0,part[1],0),gate_at+across*part[2]+Vector3(0,part[3],0),.022,"5f6a65",.7).reparent(gate,true)
	for i in 7:
		var x:=-.3+i*.1
		rod(gate_at+across*x+Vector3(0,.1,0),gate_at+across*x+Vector3(0,2.08,0),.008,"6f7a74",.7).reparent(gate,true)
	box(gate_at+across*.33+out*.05+Vector3(0,1.05,0),Vector3(.04,.11,.09),"8b7a4a",false,.8).reparent(gate,true)
	var gate_meshes:Array[MeshInstance3D]=[]
	for node in gate.get_children():gate_meshes.append(node)
	roof_door.set_meta("outline_meshes",gate_meshes)
	# Gate posts and cage sides close the bottom of the ladder.
	for side in [-1,1]:
		box(face+across*side*.44+out*.36+Vector3(0,1.1,0),Vector3(.72,2.2,.05),"000000",true).visible=false
		rod(gate_at+across*side*.44,gate_at+across*side*.44+Vector3(0,2.4,0),.03,"5d6762",.7)
	box(face+out*.25+Vector3(0,2.75,0),Vector3(.14,.12,.18),"2c302e",false,.6)
	var bulb:=sphere(face+out*.3+Vector3(0,2.66,0),Vector3(.09,.09,.09),"e2d3a6");bulb.material_override=material("e2d3a6",0,.5,1.2)
	point_light(face+out*.7+Vector3(0,2.5,0),"cdbf98",.9,6)

func deck(at:Vector3,size:Vector3, rails_x:=true,rails_z:=false) -> void:
	box(at-Vector3(0,.12,0),Vector3(size.x,.24,size.z),"4b5350",true,.5)
	var count:=maxi(1,int(size.z/.34))
	for i in count:
		var z:float=at.z-size.z*.5+(i+.5)*size.z/count
		box(Vector3(at.x,at.y+.015,z),Vector3(size.x-.07,.025,.24),"73634b")
	for side in [-1,1]:
		if rails_x:
			for h in [.5,1.1]:rod(at+Vector3(side*size.x*.5,h,-size.z*.5),at+Vector3(side*size.x*.5,h,size.z*.5),.035,"76857b",.7)
			for i in range(0,count,6):
				var z:float=-size.z*.5+i*size.z/count
				rod(at+Vector3(side*size.x*.5,0,z),at+Vector3(side*size.x*.5,1.1,z),.04,"4e635f",.7)
		if rails_z:
			for h in [.5,1.1]:rod(at+Vector3(-size.x*.5,h,side*size.z*.5),at+Vector3(size.x*.5,h,side*size.z*.5),.035,"76857b",.7)
		# Physical guard rails include a thin lower fence, without invisible floor gaps.
		if rails_x:box(at+Vector3(side*size.x*.5,.5,0),Vector3(.07,1,size.z),"4e635f",true,.65).visible=false
		if rails_z:box(at+Vector3(0,.5,side*size.z*.5),Vector3(size.x,1,.07),"4e635f",true,.65).visible=false

func make_roof() -> void:
	var y:=ROOF_FLOOR
	# Two joined wooden runs below the ridge. Their end faces touch; their top
	# surfaces never overlap. The tent cloth remains above the player's head.
	# The first run stops short of the hatch; a narrower piece reaches the mast.
	deck(Vector3(-10,y,-11.25),Vector3(3,0,15.3),true,false)
	deck(Vector3(-9.5,y,-19.45),Vector3(2,0,1.1),false,false)
	# West and east pedestal boards with the wire between them.
	deck(Vector3((-11.5+WIRE_A)*.5,y,WIRE_Z),Vector3(WIRE_A+11.5,0,3.2),false,false)
	deck(Vector3((WIRE_B+8)*.5,y,WIRE_Z),Vector3(8-WIRE_B,0,3.2),false,false)
	guard(Vector3(-11.5,y,-.4),Vector3(WIRE_A,y,-.4))
	guard(Vector3(-8.5,y,-3.6),Vector3(WIRE_A,y,-3.6))
	guard(Vector3(-11.5,y,-3.6),Vector3(-11.5,y,-.4))
	guard(Vector3(WIRE_B,y,-.4),Vector3(8,y,-.4))
	guard(Vector3(WIRE_B,y,-3.6),Vector3(EAST_MAST_X-1.5,y,-3.6))
	guard(Vector3(8,y,-3.6),Vector3(8,y,-.4))
	for x in [WIRE_A,WIRE_B]:
		# Board ends are railed except a narrow gap where the wire starts.
		guard(Vector3(x,y,-3.6),Vector3(x,y,WIRE_Z-.42))
		guard(Vector3(x,y,WIRE_Z+.42),Vector3(x,y,-.4))
		# Wire stand: a short post with a cable cleat at boot height.
		rod(Vector3(x,y,WIRE_Z),Vector3(x,y+.35,WIRE_Z),.05,"3c3f3b",.6)
	rod(Vector3(WIRE_A,y+.03,WIRE_Z),Vector3(WIRE_B,y+.03,WIRE_Z),.018,"8d8f88",.85)
	# Guy lines from the board posts out to the masts keep the wire taut.
	for x in [WIRE_A,WIRE_B]:
		var out:=-1.0 if x<0 else 1.0
		rod(Vector3(x,y+.35,WIRE_Z),Vector3(x+out*1.2,y-.25,WIRE_Z-1.5),.012,"6e6f68",.8)
		rod(Vector3(x,y+.35,WIRE_Z),Vector3(x+out*1.2,y-.25,WIRE_Z+1.5),.012,"6e6f68",.8)
	# Walkable strip on the wire; the tightrope script keeps Richard centred.
	var strip:=box(Vector3((WIRE_A+WIRE_B)*.5,y-.1,WIRE_Z),Vector3(WIRE_B-WIRE_A+.1,.2,.4),"000000",true)
	strip.visible=false
	# The east run mirrors the west one and ends at the second mast's winch.
	deck(Vector3(EAST_MAST_X,y,-11.25),Vector3(3,0,15.3),true,false)
	guard(Vector3(EAST_MAST_X-1.5,y,-18.9),Vector3(EAST_MAST_X+1.5,y,-18.9))
	box(Vector3(EAST_MAST_X,y+.35,-18.4),Vector3(1.1,.7,.6),"3d433f",true,.6)
	cylinder(Vector3(EAST_MAST_X,y+.82,-18.4),.28,.9,"6b5f4a").rotation.z=PI/2
	# Hatch rails on three sides; the fourth side is the ladder itself.
	guard(Vector3(-11.5,y,-20),Vector3(-8.5,y,-20))
	guard(Vector3(-8.5,y,-20),Vector3(-8.5,y,-18.9))
	guard(Vector3(-11.5,y,-20),Vector3(-11.5,y,-18.9))
	guard(Vector3(-11.5,y,-18.9),Vector3(HATCH_X,y,-18.9))
	box(Vector3(-11,y-.12,-18.9),Vector3(1,.24,.08),"4b5350",false,.5)
	box(Vector3(HATCH_X,y-.12,-19.45),Vector3(.08,.24,1.1),"4b5350",false,.5)
	# A chain between the stiles; the player descends through interaction only.
	for i in 6:
		var a:=Vector3(HATCH_X-.04,y+.95-sin(PI*i/6)*.12,MAST.z-.24+i*.48/6)
		var b:=Vector3(HATCH_X-.04,y+.95-sin(PI*(i+1)/6)*.12,MAST.z-.24+(i+1)*.48/6)
		rod(a,b,.012,"8f8a72",.8)
	box(Vector3(HATCH_X,y+.5,MAST.z),Vector3(.07,1,.5),"000000",true).visible=false
	# The east post stands past the trampoline frame (x 4.15..6.45).
	for x in [-8,7.7]:
		rod(Vector3(x,y,-2),Vector3(x,y+3.1,-2),.035,"5b5445",.55)
		box(Vector3(x,y-.3,-2),Vector3(.16,.35,3.5),"4f3f30")
	for entry in [[Vector3(-10,y+2.4,-17),"c1d0d5"],[Vector3(-10,y+2.4,-5),"bfaa72"],[Vector3(7.6,y+2.2,-3.3),"d0b98b"],[Vector3(EAST_MAST_X,y+2.4,-11),"bfaa72"]]:
		var bulb:=sphere(entry[0],Vector3(.14,.22,.14),entry[1]);bulb.material_override=material(entry[1],0,.5,1.4)
		point_light(entry[0],entry[1],1.2,10)
		rod(entry[0],entry[0]+Vector3(0,1,0),.025,"444f50")
	# The single attached torn flap belongs to stage_show; no floating strips.
	# Hung on the inside of the west handrail rather than in the air above it.
	plaque("РЕМОНТ КУПОЛА\nДЕРЖАТЬСЯ ПЕРИЛ",Vector3(-11.43,y+.78,-15),2.2,.62,PI/2)
	var return_target:=target("roof_return",ROOF_RETURN,Vector3(.7,1.3,.35),"Спуститься по лестнице")
	return_target.set_meta("outline_meshes",ladder_top)
	for piece in ladder_top:piece.set_meta("dynamic_set",true)
	# The rope and suspended medicine bag form the explicit ending condition.
	rope_piece=rod(ROPE+Vector3(0,2.8,0),ROPE-Vector3(0,.5,0),.025,"a18b5f")
	rope_piece.set_meta("dynamic_set",true)
	medicine_bag=Node3D.new();medicine_bag.name="MedicineBag";medicine_bag.set_meta("dynamic_set",true);add_child(medicine_bag)
	var bag:=box(ROPE-Vector3(0,.35,0),Vector3(.5,.65,.3),"777459")
	bag.reparent(medicine_bag,true)
	var cross1:=box(ROPE+Vector3(0,-.3,.165),Vector3(.26,.07,.02),"bfb99a")
	var cross2:=box(ROPE+Vector3(0,-.3,.165),Vector3(.07,.26,.02),"bfb99a")
	cross1.reparent(medicine_bag,true);cross2.reparent(medicine_bag,true)
	var rope_target:=target("roof_rope",ROPE,Vector3(.7,1.2,.5),"Осмотреть трос")
	rope_target.set_meta("outline_meshes",[rope_piece,bag])
	# A full trampoline frame, woven bed, many springs and old shoe marks.
	var t:=Vector3(TRAMPOLINE.x,y,TRAMPOLINE.z)
	for side in [-1,1]:
		rod(t+Vector3(side*1.15,.65,-.95),t+Vector3(side*1.15,.65,.95),.065,"8b9487",.7)
		rod(t+Vector3(-1.15,.65,side*.95),t+Vector3(1.15,.65,side*.95),.065,"8b9487",.7)
		for z in [-.75,.75]:rod(t+Vector3(side*.9,.05,z),t+Vector3(side*.9,.65,z),.055,"657b73",.65)
	box(t+Vector3(0,.61,0),Vector3(1.85,.045,1.45),"30494b")
	for index in 13:
		var x:float=-.9+index*.15
		for side in [-1,1]:rod(t+Vector3(x,.64,side*.72),t+Vector3(x,.64,side*.95),.018,"9ba38b",.7)
	for side in [-1,1]:
		var print:=box(t+Vector3(side*.22,.64,0),Vector3(.16,.007,.4),"625e4d")
		print.rotation.y=side*.15
	plaque("ШАНС",t+Vector3(0,.7,-.96),.8,.22,PI)
	var chance:=sign_text("ШАНС",t+Vector3(0,.65,.35),.7,0,"beae85")
	chance.rotation=Vector3(-PI/2,-PI/2,0)
	var tramp_target:=target("trampoline",t+Vector3(0,.95,-.8),Vector3(2.2,.7,.4),"Осмотреть батут")
	# Outline only the trampoline itself: bed and frame, not the rails behind.
	var visible: Array[MeshInstance3D]=[]
	for node in get_children():
		if node is MeshInstance3D and node.position.distance_to(t+Vector3(0,.6,0))<1.6 and node.position.y>t.y+.55 and node.position.y<t.y+.75:
			node.set_meta("dynamic_set",true);visible.append(node)
	tramp_target.set_meta("outline_meshes",visible)
	asset("rope_coil",t+Vector3(-2,.04,0),.6,.65,false)
	# A folded note on the boards past the trampoline, under the corner lamp.
	var note_at:=Vector3(7.15,y+.015,-1.2)
	var sheet:=box(note_at,Vector3(.21,.006,.28),"e3d9bf");sheet.rotation.y=.35
	var crease:=box(note_at+Vector3(0,.004,0),Vector3(.21,.002,.006),"b9ad90");crease.rotation.y=.35
	var scrawl:=sign_text("Точно ли это то,\nчего ты хочешь,\nРичард?",note_at+Vector3(0,.006,0),.16,0,"3a3140")
	scrawl.rotation=Vector3(-PI/2,.35,0);scrawl.outline_size=0
	for piece in [sheet,crease]:piece.set_meta("dynamic_set",true)
	var note_target:=target("roof_note",note_at+Vector3(0,.15,0),Vector3(.6,.35,.6),"Поднять записку")
	note_target.set_meta("outline_meshes",[sheet])

func is_roof_position(at: Vector3) -> bool:
	if at.y < ROOF_FLOOR - 1 or at.y > ROOF_FLOOR + 5: return false
	return (at.x >= -11.6 and at.x <= -8.4 and at.z >= -20.1 and at.z <= -3.5) or (at.x >= EAST_MAST_X-1.6 and at.x <= EAST_MAST_X+1.6 and at.z >= -19 and at.z <= -3.5) or (at.x >= -11.6 and at.x <= 8.1 and at.z >= -3.7 and at.z <= -.3)

func guard(a:Vector3,b:Vector3) -> void:
	for height in [.5,1.1]:rod(a+Vector3(0,height,0),b+Vector3(0,height,0),.035,"76857b",.7)
	var count:=maxi(1,int(a.distance_to(b)/2))
	for i in count+1:
		var p:Vector3=a.lerp(b,float(i)/count)
		rod(p,p+Vector3(0,1.1,0),.04,"4e635f",.7)
	var dimensions:=Vector3(maxf(.07,absf(a.x-b.x)),1,maxf(.07,absf(a.z-b.z)))
	box((a+b)*.5+Vector3(0,.5,0),dimensions,"4e635f",true,.65).visible=false

func room_shell(center:Vector3,width:float,depth:float,color:String,door_x:=0.0,door_front:=false) -> void:
	box(center-Vector3(0,.1,0),Vector3(width,.2,depth),color,true)
	box(center+Vector3(0,3,0),Vector3(width,.15,depth),"b1b1a2",true)
	for side in [-1,1]:box(center+Vector3(side*width*.5,1.5,0),Vector3(.15,3,depth),"a9aa99",true)
	var back_z:float=center.z-depth*.5
	box(Vector3(center.x,1.5,back_z),Vector3(width,3,.15),"a7aaa0",true)
	if not door_front:box(center+Vector3(0,1.5,depth*.5),Vector3(width,3,.15),"a7aaa0",true)
	else:
		for side in [-1,1]:box(center+Vector3(side*(width*.25+.4),1.5,depth*.5),Vector3(width*.5-.8,3,.15),"a7aaa0",true)
		box(center+Vector3(0,2.65,depth*.5),Vector3(1.6,.7,.15),"a7aaa0",true)

func make_home() -> void:
	var c:=Vector3(155,0,0)
	room_shell(c,8,8,"746552")
	# Open doorway on the north wall joins the bedroom to a separate bathroom.
	# Remove only our bedroom wall here, leaving the supplied circus entirely alone.
	for node in get_children():
		if node is MeshInstance3D and node.position.distance_to(c+Vector3(0,1.5,-4))<.01:
			node.hide();node.queue_free()
	for side in [-1,1]:box(c+Vector3(side*2.35,1.5,-4),Vector3(3.3,3,.15),"a7aaa0",true)
	box(c+Vector3(0,2.65,-4),Vector3(1.4,.7,.15),"a7aaa0",true)
	room_shell(c+Vector3(0,0,-7.5),5,7,"8c9690",0,true)
	for i in 15:box(c+Vector3(-3.7+i*.52,.012,0),Vector3(.015,.008,7.8),"514d42")
	# Furniture stands against the walls and in the corners; the middle of the
	# room, the x=0 line and the north doorway stay open for the walk to the mirror.
	asset("victorian_bed",c+Vector3(-3.16,0,2.8),0,1,true)
	asset("wardrobe",c+Vector3(3.08,0,3.52),PI,1,true)
	table(c+Vector3(-2.6,0,-3.55),1.1,.65)
	cylinder(c+Vector3(-2.6,1.16,-3.55),.20,.4,"c7b791")
	var shade:=CylinderMesh.new();shade.bottom_radius=.32;shade.top_radius=.21;shade.height=.34
	mesh_node(shade,c+Vector3(-2.6,1.5,-3.55),material("dbc28e",0,.8,.5))
	point_light(c+Vector3(-2.6,1.45,-3.3),"e9c486",.9,5)
	# Bedside table in the gap between the bed and the shelves, on the west wall.
	table(c+Vector3(-3.6,0,1.25),.5,.5)
	# Shelving unit along the west wall: two side panels, shelves, books and boxes.
	for z in [-2.35,-.35]:box(c+Vector3(-3.76,1.0,z),Vector3(.3,2.0,.05),"4b3b2d",true,0.0,"SetPanel","wood")
	for h in [.05,.55,1.05,1.55,2.0]:box(c+Vector3(-3.76,h,-1.35),Vector3(.3,.04,2.05),"5b4633",h==.05,0.0,"SetPanel","wood")
	box(c+Vector3(-3.92,1.0,-1.35),Vector3(.02,2.0,2.0),"3b2f25")
	for i in 7:box(c+Vector3(-3.76,.78,-2.2+i*.12),Vector3(.2,.38-(i%3)*.04,.08),["7a3b3b","3d5a52","8f7a47"][i%3])
	for i in 4:box(c+Vector3(-3.76,1.28,-1.0+i*.3),Vector3(.2,.4,.12+(i%2)*.1),["a68e5a","6f7f8a"][i%2])
	box(c+Vector3(-3.76,1.74,-.8),Vector3(.24,.3,.4),"8c7a58")
	box(c+Vector3(-3.76,.3,-1.55),Vector3(.24,.4,.5),"6d5a40")
	box(c+Vector3(.3,.02,.5),Vector3(3.1,.025,2.7),"5e776e")
	# Window frame, curtains, daylight card and a narrow sill.
	box(c+Vector3(3.90,1.85,-.6),Vector3(.025,1.7,2.3),"849fa2")
	for z in [-1.8,-.6,.6]:box(c+Vector3(3.85,1.85,z),Vector3(.07,1.8,.055),"e0d8bc")
	for h in [1,1.85,2.7]:box(c+Vector3(3.85,h,-.6),Vector3(.07,.055,2.5),"e0d8bc")
	for z in [-2,.85]:box(c+Vector3(3.72,1.8,z),Vector3(.16,2.5,.4),"6a7971")
	point_light(c+Vector3(2.8,2,-.6),"d6e2db",2.6,7)
	# Old show posters from the passage, pinned up at home.
	for i in 3:
		var poster:=preload("res://scripts/scene_parts.gd").new();add_child(poster)
		poster.position=c+Vector3(-1.8+i*1.7,1.9,3.91);poster.rotation.y=PI
		poster.box(Vector3.ZERO,Vector3(.9,1.36,.02),"aa9875")
		var art:Texture2D=load(["res://assets/characters/colored/mordecai.png","res://assets/characters/colored/bruno.png","res://assets/characters/colored/elsa.png"][i])
		var ratio:float=art.get_width()/float(art.get_height())
		var picture:=QuadMesh.new();picture.size=Vector2(minf(.66,.72*ratio),minf(.72,.66/ratio))
		var ink:=StandardMaterial3D.new();ink.albedo_texture=art;ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;ink.roughness=1
		poster.mesh_node(picture,Vector3(0,.02,.015),ink)
		poster.sign_text(["МОРДЕКАЙ","БРУНО","ЭЛЬЗА"][i],Vector3(0,.51,.015),.7,0,"4d3035")
		poster.sign_text("LAST SHOW",Vector3(0,-.52,.015),.68,0,"563a3c")
	table(c+Vector3(2.6,0,-3.55),1.6,.6)
	var toy:Node3D=load("res://assets/characters/models/mordecai.glb").instantiate()
	toy.position=c+Vector3(2.6,.91,-3.55);toy.scale=Vector3.ONE*.15;add_child(toy)
	for animator in toy.find_children("*","AnimationPlayer",true,false):animator.stop()
	for mesh in toy.find_children("*","MeshInstance3D",true,false):mesh.layers=1
	# Physical bathroom fixtures and a live mirror.
	var sink:=c+Vector3(0,.86,-10.5)
	box(sink-Vector3(0,.42,0),Vector3(1,.82,.7),"c0c8b8",true)
	box(sink,Vector3(1.2,.14,.8),"d9ddd1",true)
	box(sink+Vector3(0,.08,0),Vector3(.72,.025,.47),"6f8984")
	rod(sink+Vector3(0,.08,-.25),sink+Vector3(0,.45,-.25),.035,"b5beb0",.8)
	rod(sink+Vector3(0,.45,-.25),sink+Vector3(0,.45,-.02),.035,"b5beb0",.8)
	box(HOME_MIRROR-Vector3(0,0,.05),Vector3(1.45,1.6,.08),"5f6b60")
	var glass:=QuadMesh.new();glass.size=Vector2(1.25,1.4)
	bathroom_glass=mesh_node(glass,HOME_MIRROR,material("a0b0a0"),"HomeMirrorGlass")
	bathroom_glass.set_meta("dynamic_set",true)
	var mirror_target:=target("home_mirror",HOME_MIRROR+Vector3(0,0,.06),Vector3(1.25,1.4,.1),"Посмотреть в зеркало")
	mirror_target.set_meta("outline_meshes",[bathroom_glass])
	var bottle:=c+Vector3(.42,.935,-10.45)
	cylinder(bottle+Vector3(0,.1,0),.075,.2,"7a5a2d")
	box(bottle+Vector3(0,.12,.073),Vector3(.11,.12,.008),"d0cdb4")
	pill_cap=cylinder(bottle+Vector3(0,.22,0),.08,.045,"d4d8c8")
	pill_cap.set_meta("dynamic_set",true)
	for i in 4:
		var pill:=cylinder(bottle+Vector3(-.15-i*.07,.015,.03*(i%2)),.025,.01,"cdd6c4")
		pill.set_meta("dynamic_set",true);loose_pills.append(pill)
	point_light(HOME_MIRROR+Vector3(0,1,.5),"d8e3d6",1.4,5)
	# Towels on short wall rails either side of the sink.
	for side in [-1,1]:
		rod(c+Vector3(side*2.38,1.62,-9.05),c+Vector3(side*2.38,1.62,-8.15),.02,"8f9d90",.7)
		for end in [-9.05,-8.15]:rod(c+Vector3(side*2.43,1.62,end),c+Vector3(side*2.38,1.62,end),.015,"8f9d90",.7)
		box(c+Vector3(side*2.38,1.25,-8.6),Vector3(.05,.74,.7),["7f97a6","b7a27f"][(side+1)/2],true,0.0,"HomeTowel","cloth")

func sync() -> void:
	for pill in loose_pills:pill.visible=game.flags.get("rope_cut",false)
	rope_piece.visible=not game.flags.get("rope_cut",false)
	medicine_bag.visible=not game.flags.get("rope_cut",false)
	pill_cap.position=Vector3(155.65,.95,-10.3) if game.flags.get("rope_cut",false) else Vector3(155.42,1.155,-10.45)
